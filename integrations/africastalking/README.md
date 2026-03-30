# Africa's Talking Integration (USSD + SMS)

This service exposes a **single short code USSD menu** with SMS actions embedded in the flow.

- **USSD short code**: `*789*5758#`
- **USSD endpoint**: `POST /ussd`
- **SMS endpoint**: `POST /sms`
- **Health**: `GET /health`

## Features (MVP)

- Wallet balance + OMNI to KES swap
- Learn-to-earn daily tasks via SMS
- Guild dashboard, contracts, bids, and withdrawals
- SMS commands: `JOIN`, `BAL`, `PROGRESS`, `PAYOUT <amt>`, `TASK <id> <answer>`, `OTP <code>`

## Environment Variables

- `AT_USERNAME` / `AT_API_KEY` (Africa's Talking)
- `AT_SENDER_ID` (optional sender ID)
- `AT_SMS_URL` (override SMS API base)
- `OMNI_TO_KES` (default: `1`)
- `OMNI_OTP_TTL_MIN` (default: `10`)
- `PORT` (default: `8010`)

## Run Locally

```bash
cd integrations/africastalking
python africastalking_gateway.py
```

## Sample USSD Request

```bash
curl -X POST http://localhost:8010/ussd \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d 'sessionId=abc123&serviceCode=*789*5758#&phoneNumber=+254700000000&text=1*1'
```

## Sample SMS Request

```bash
curl -X POST http://localhost:8010/sms \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d 'from=+254700000000&text=BAL'
```

## Notes

- USSD must respond fast, so heavy operations should be queued in production.
- SMS sending will log to console if `AT_USERNAME`/`AT_API_KEY` are not set.
