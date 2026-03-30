"""
Africa's Talking USSD + SMS Gateway for OMNIVERSITY
Single short code flow with SMS actions inside USSD.

USSD:  *789*5758#
SMS:   JOIN, BAL, PROGRESS, PAYOUT <amt>, TASK <id> <answer>, OTP <code>
"""

from __future__ import annotations

import json
import os
import random
import string
from dataclasses import dataclass, asdict
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Optional
from urllib.parse import parse_qs
from urllib.request import Request, urlopen
from urllib.parse import urlencode

from fastapi import FastAPI, Request as FastAPIRequest
from fastapi.responses import PlainTextResponse, JSONResponse

APP_NAME = "OMNIVERSITY"
SHORT_CODE = "*789*5758#"
DATA_DIR = Path(__file__).parent / "data"
STATE_FILE = DATA_DIR / "state.json"

OMNI_TO_KES = float(os.getenv("OMNI_TO_KES", "1"))
OTP_TTL_MIN = int(os.getenv("OMNI_OTP_TTL_MIN", "10"))

AT_USERNAME = os.getenv("AT_USERNAME", "")
AT_API_KEY = os.getenv("AT_API_KEY", "")
AT_SENDER_ID = os.getenv("AT_SENDER_ID", "")
AT_SMS_URL = os.getenv("AT_SMS_URL", "https://api.africastalking.com/version1/messaging")

app = FastAPI(title="OMNIVERSITY Africa's Talking Gateway", version="1.0.0")


@dataclass
class Task:
    task_id: str
    title: str
    reward: int
    prompt: str


@dataclass
class Guild:
    name: str
    members: int
    contracts: List[str]
    monthly_earnings: int


@dataclass
class UserProfile:
    phone: str
    omni_balance: int = 150
    kes_balance: int = 300
    streak_days: int = 3
    total_earned: int = 420
    active_guild: Optional[Guild] = None
    transactions: List[str] = None

    def __post_init__(self) -> None:
        if self.transactions is None:
            self.transactions = [
                "+20 OMNI Python Course",
                "-10 OMNI Staked for AI Module",
                "+40 OMNI Guild payout",
            ]
        if self.active_guild is None:
            self.active_guild = Guild(
                name="NairobiDevs",
                members=42,
                contracts=["Farm App (50,000 OMNI)", "School Debug (5,000 OMNI)"],
                monthly_earnings=1000,
            )


DEFAULT_TASKS = [
    Task("T1", "Intro to Solidity", 10, "Read the intro and answer: What is a smart contract?"),
    Task("T2", "Python Problem", 5, "Solve: What is the output of print(2**3)?"),
]


class StateStore:
    def __init__(self) -> None:
        self.users: Dict[str, UserProfile] = {}
        self.pending_otps: Dict[str, Dict[str, str]] = {}
        self.pending_swaps: Dict[str, Dict[str, int]] = {}
        self._load()

    def _load(self) -> None:
        if not STATE_FILE.exists():
            return
        try:
            payload = json.loads(STATE_FILE.read_text())
        except json.JSONDecodeError:
            return
        for phone, data in payload.get("users", {}).items():
            guild_data = data.get("active_guild")
            guild = None
            if guild_data:
                guild = Guild(**guild_data)
            user = UserProfile(
                phone=phone,
                omni_balance=data.get("omni_balance", 150),
                kes_balance=data.get("kes_balance", 300),
                streak_days=data.get("streak_days", 3),
                total_earned=data.get("total_earned", 420),
                active_guild=guild,
                transactions=data.get("transactions") or [],
            )
            self.users[phone] = user
        self.pending_otps = payload.get("pending_otps", {})
        self.pending_swaps = payload.get("pending_swaps", {})

    def _save(self) -> None:
        DATA_DIR.mkdir(parents=True, exist_ok=True)
        payload = {
            "users": {phone: asdict(user) for phone, user in self.users.items()},
            "pending_otps": self.pending_otps,
            "pending_swaps": self.pending_swaps,
        }
        STATE_FILE.write_text(json.dumps(payload, indent=2))

    def get_user(self, phone: str) -> UserProfile:
        if phone not in self.users:
            self.users[phone] = UserProfile(phone=phone)
            self._save()
        return self.users[phone]

    def set_user(self, user: UserProfile) -> None:
        self.users[user.phone] = user
        self._save()

    def create_otp(self, phone: str, reason: str, amount: int) -> str:
        code = "".join(random.choice(string.digits) for _ in range(4))
        self.pending_otps[phone] = {
            "code": code,
            "reason": reason,
            "amount": amount,
            "expires": (datetime.utcnow() + timedelta(minutes=OTP_TTL_MIN)).isoformat(),
        }
        self._save()
        return code

    def verify_otp(self, phone: str, code: str) -> Optional[Dict[str, str]]:
        data = self.pending_otps.get(phone)
        if not data:
            return None
        if data.get("code") != code:
            return None
        expires = datetime.fromisoformat(data.get("expires"))
        if datetime.utcnow() > expires:
            self.pending_otps.pop(phone, None)
            self._save()
            return None
        self.pending_otps.pop(phone, None)
        self._save()
        return data


state = StateStore()


def menu(lines: List[str], end: bool = False) -> str:
    prefix = "END" if end else "CON"
    return prefix + " " + "\n".join(lines)


def fmt_kes(omni_amount: int) -> int:
    return int(round(omni_amount * OMNI_TO_KES))


def clean_amount(value: str) -> Optional[int]:
    try:
        amount = int(float(value))
    except ValueError:
        return None
    return amount if amount > 0 else None


def send_sms(to_number: str, message: str) -> None:
    if not (AT_USERNAME and AT_API_KEY):
        print(f"[SMS:demo] {to_number}: {message}")
        return

    payload = {
        "username": AT_USERNAME,
        "to": to_number,
        "message": message,
    }
    if AT_SENDER_ID:
        payload["from"] = AT_SENDER_ID

    data = urlencode(payload).encode("utf-8")
    req = Request(AT_SMS_URL, data=data)
    req.add_header("apiKey", AT_API_KEY)
    req.add_header("Content-Type", "application/x-www-form-urlencoded")

    try:
        with urlopen(req, timeout=5) as _:
            return
    except Exception as exc:
        print(f"[SMS:error] {exc}")


def build_wallet_menu(user: UserProfile, parts: List[str]) -> str:
    if len(parts) == 1:
        return menu([
            "1. Balance",
            "2. Swap OMNI to KES",
            "3. Recent Tx",
        ])

    choice = parts[1]
    if choice == "1":
        return menu([
            f"OMNI: {user.omni_balance} (KES {fmt_kes(user.omni_balance)})",
            f"KES Wallet: {user.kes_balance}",
        ], end=True)

    if choice == "2":
        if len(parts) == 2:
            return menu(["Enter OMNI amount:"])
        if len(parts) == 3:
            amount = clean_amount(parts[2])
            if amount is None:
                return menu(["Invalid amount.", "Enter OMNI amount:"], end=False)
            kes_value = fmt_kes(amount)
            return menu([
                f"{amount} OMNI = KES {kes_value}",
                "Confirm? 1.Yes 2.No",
            ])
        if len(parts) == 4:
            amount = clean_amount(parts[2]) or 0
            if parts[3] == "1" and amount > 0:
                otp = state.create_otp(user.phone, "swap", amount)
                send_sms(user.phone, f"OMNIVERSITY OTP: {otp}. Reply: OTP {otp} to confirm swap.")
                return menu(["OTP sent by SMS.", "Reply: OTP <code>"], end=True)
            return menu(["Swap cancelled."], end=True)

    if choice == "3":
        recent = user.transactions[:3]
        return menu(["Recent:"] + recent, end=True)

    return menu(["Invalid option"], end=True)


def build_learn_menu(user: UserProfile, parts: List[str]) -> str:
    if len(parts) == 1:
        return menu([
            "1. Today\'s Tasks",
            "2. Check Streak",
            "3. Submit Proof",
        ])

    choice = parts[1]
    if choice == "1":
        if len(parts) == 2:
            lines = [
                f"1. {DEFAULT_TASKS[0].title} +{DEFAULT_TASKS[0].reward}",
                f"2. {DEFAULT_TASKS[1].title} +{DEFAULT_TASKS[1].reward}",
            ]
            return menu(lines)
        task_choice = parts[2] if len(parts) > 2 else ""
        if task_choice in ("1", "2"):
            task = DEFAULT_TASKS[int(task_choice) - 1]
            send_sms(
                user.phone,
                f"Task {task.task_id}: {task.title}. {task.prompt} Reply: TASK {task.task_id} <answer>"
            )
            return menu(["Task sent by SMS."], end=True)
        return menu(["Invalid task"], end=True)

    if choice == "2":
        return menu([f"Streak: {user.streak_days} days", "Next reward: 2x OMNI"], end=True)

    if choice == "3":
        return menu(["Submit by SMS:", "TASK T1 <answer>"], end=True)

    return menu(["Invalid option"], end=True)


def build_guild_menu(user: UserProfile, parts: List[str]) -> str:
    if len(parts) == 1:
        return menu([
            "1. My Guild",
            "2. Contracts",
            "3. Bid",
            "4. Claim Earnings",
        ])

    choice = parts[1]
    guild = user.active_guild
    if choice == "1" and guild:
        return menu([
            f"{guild.name}",
            f"Members: {guild.members}",
            "Active contracts: 2",
        ], end=True)

    if choice == "2" and guild:
        if len(parts) == 2:
            return menu([
                "1. " + guild.contracts[0],
                "2. " + guild.contracts[1],
            ])
        contract_choice = parts[2] if len(parts) > 2 else ""
        if contract_choice in ("1", "2"):
            send_sms(user.phone, f"Contract: {guild.contracts[int(contract_choice)-1]}")
            return menu(["Contract sent by SMS."], end=True)
        return menu(["Invalid contract"], end=True)

    if choice == "3":
        if len(parts) == 2:
            return menu(["Enter bid (OMNI):"])
        if len(parts) == 3:
            amount = clean_amount(parts[2])
            if amount is None:
                return menu(["Invalid amount.", "Enter bid (OMNI):"])
            return menu([f"Bid {amount} OMNI?", "1.Yes 2.No"])
        if len(parts) == 4:
            amount = clean_amount(parts[2]) or 0
            if parts[3] == "1" and amount > 0:
                otp = state.create_otp(user.phone, "bid", amount)
                send_sms(user.phone, f"Bid OTP: {otp}. Reply: OTP {otp} to confirm bid.")
                return menu(["OTP sent by SMS."], end=True)
            return menu(["Bid cancelled."], end=True)

    if choice == "4" and guild:
        if len(parts) == 2:
            return menu([
                f"Earnings: {guild.monthly_earnings} OMNI",
                "1. Withdraw",
                "2. Reinvest",
            ])
        if len(parts) == 3:
            if parts[2] == "1":
                otp = state.create_otp(user.phone, "withdraw", guild.monthly_earnings)
                send_sms(user.phone, f"Withdraw OTP: {otp}. Reply: OTP {otp} to confirm.")
                return menu(["OTP sent by SMS."], end=True)
            if parts[2] == "2":
                return menu(["Reinvested to guild pool."], end=True)

    return menu(["Invalid option"], end=True)


def ussd_flow(phone: str, text: str) -> str:
    user = state.get_user(phone)
    parts = [p for p in text.split("*") if p]

    if not parts:
        return menu([
            f"{APP_NAME}",
            "1. OMNI Wallet",
            "2. Learn-to-Earn",
            "3. Guild Hub",
            "4. Support",
        ])

    if parts[0] == "1":
        return build_wallet_menu(user, parts)
    if parts[0] == "2":
        return build_learn_menu(user, parts)
    if parts[0] == "3":
        return build_guild_menu(user, parts)
    if parts[0] == "4":
        return menu(["Support", "SMS: HELP", "Email: support@omniversity.africa"], end=True)

    return menu(["Invalid option"], end=True)


def sms_response(phone: str, text: str) -> str:
    user = state.get_user(phone)
    message = text.strip()
    upper = message.upper()

    if upper.startswith("JOIN"):
        otp = state.create_otp(phone, "join", 0)
        send_sms(phone, f"Welcome to {APP_NAME}. OTP: {otp}. Reply: OTP {otp} to confirm.")
        return "OTP sent. Reply: OTP <code>"

    if upper.startswith("OTP"):
        parts = upper.split()
        if len(parts) < 2:
            return "Send: OTP 1234"
        code = parts[1]
        record = state.verify_otp(phone, code)
        if not record:
            return "Invalid or expired OTP."
        reason = record.get("reason", "")
        amount = int(record.get("amount", 0))
        if reason == "swap":
            if user.omni_balance >= amount:
                user.omni_balance -= amount
                user.kes_balance += fmt_kes(amount)
                user.transactions.insert(0, f"- {amount} OMNI swap")
                state.set_user(user)
                return f"Swap complete. New OMNI: {user.omni_balance}"
            return "Insufficient OMNI balance."
        if reason == "withdraw":
            user.omni_balance = max(user.omni_balance - amount, 0)
            user.kes_balance += fmt_kes(amount)
            user.transactions.insert(0, f"- {amount} OMNI guild withdraw")
            state.set_user(user)
            return "Withdrawal queued to M-Pesa."
        if reason == "bid":
            return "Bid confirmed. Guild voting opened."
        return "OTP confirmed."

    if upper.startswith("BAL"):
        return f"OMNI: {user.omni_balance} (KES {fmt_kes(user.omni_balance)}). KES Wallet: {user.kes_balance}."

    if upper.startswith("PROGRESS"):
        return f"Streak: {user.streak_days} days. Total earned: {user.total_earned} OMNI."

    if upper.startswith("PAYOUT"):
        parts = upper.split()
        if len(parts) < 2:
            return "Send: PAYOUT <amount>"
        amount = clean_amount(parts[1])
        if amount is None:
            return "Invalid amount."
        otp = state.create_otp(phone, "swap", amount)
        send_sms(phone, f"Payout OTP: {otp}. Reply: OTP {otp} to confirm.")
        return "OTP sent. Reply: OTP <code>"

    if upper.startswith("TASK"):
        parts = message.split(maxsplit=2)
        if len(parts) < 3:
            return "Format: TASK T1 <answer>"
        task_id = parts[1].upper()
        task = next((t for t in DEFAULT_TASKS if t.task_id == task_id), None)
        if not task:
            return "Unknown task."
        user.omni_balance += task.reward
        user.total_earned += task.reward
        user.transactions.insert(0, f"+{task.reward} OMNI {task.title}")
        state.set_user(user)
        return f"Task accepted. +{task.reward} OMNI credited."

    if upper.startswith("HELP") or upper.startswith("MENU"):
        return "Commands: JOIN, BAL, PROGRESS, PAYOUT <amt>, TASK <id> <answer>, OTP <code>"

    return "Unknown command. Send HELP for options."


@app.post("/ussd")
async def ussd_endpoint(request: FastAPIRequest) -> PlainTextResponse:
    raw = await request.body()
    data = parse_qs(raw.decode("utf-8"))
    phone = (data.get("phoneNumber") or [""])[0]
    text = (data.get("text") or [""])[0]
    response = ussd_flow(phone, text)
    return PlainTextResponse(response, media_type="text/plain")


@app.post("/sms")
async def sms_endpoint(request: FastAPIRequest) -> PlainTextResponse:
    raw = await request.body()
    data = parse_qs(raw.decode("utf-8"))
    phone = (data.get("from") or data.get("phoneNumber") or [""])[0]
    text = (data.get("text") or [""])[0]
    message = sms_response(phone, text)
    return PlainTextResponse(message, media_type="text/plain")


@app.get("/health")
async def health() -> JSONResponse:
    return JSONResponse({"status": "ok", "service": "africastalking"})


if __name__ == "__main__":
    try:
        import uvicorn
    except ImportError:
        raise SystemExit("Install uvicorn to run: pip install uvicorn")
    port = int(os.getenv("PORT", "8010"))
    uvicorn.run(app, host="0.0.0.0", port=port)
