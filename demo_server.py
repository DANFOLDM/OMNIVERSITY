import json
import os
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse

HOST = "0.0.0.0"
PORT = int(os.getenv("PORT", "9000"))

profiles = {}


def json_response(handler, payload, status=200):
    handler.send_response(status)
    handler.send_header("Content-Type", "application/json")
    handler.send_header("Access-Control-Allow-Origin", "*")
    handler.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
    handler.send_header("Access-Control-Allow-Headers", "Content-Type")
    handler.end_headers()
    handler.wfile.write(json.dumps(payload).encode("utf-8"))


def read_json(handler):
    length = int(handler.headers.get("Content-Length", "0") or "0")
    if length == 0:
        return {}
    raw = handler.rfile.read(length)
    try:
        return json.loads(raw.decode("utf-8"))
    except json.JSONDecodeError:
        return {}


class DemoHandler(BaseHTTPRequestHandler):
    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_GET(self):
        path = urlparse(self.path).path
        if path == "/health":
            return json_response(self, {"status": "ok"})

        if path.startswith("/profile/"):
            user_id = path.split("/profile/")[-1]
            profile = profiles.get(user_id)
            if profile:
                return json_response(self, profile)
            return json_response(self, {"error": "Profile not found"})

        if path.startswith("/market-insights/"):
            region = path.split("/market-insights/")[-1] or "Africa"
            return json_response(self, {
                "region": region,
                "top_roles": ["React Developer", "Data Analyst", "Blockchain Engineer"]
            })

        return json_response(self, {"error": "Not found"}, status=404)

    def do_POST(self):
        path = urlparse(self.path).path
        body = read_json(self)

        if path == "/profile":
            user_id = body.get("user_id", "judge_demo")
            profiles[user_id] = {
                "user_id": user_id,
                "name": body.get("name", "Judge Demo"),
                "email": body.get("email", "judge@elimucoin.test"),
                "skill_graph": {"React": 4, "Node": 3, "Solidity": 2},
                "learning_style": body.get("learning_style", "visual"),
                "preferred_language": body.get("preferred_language", "en"),
                "total_omni_earned": 420,
                "modules_completed": 12,
                "current_streak": 6,
                "weak_areas": ["Testing"],
                "strong_areas": ["React"],
                "learning_goals": body.get("learning_goals", []),
            }
            return json_response(self, {"message": "Profile created successfully"})

        if path == "/chat":
            user_id = body.get("user_id", "judge_demo")
            message = body.get("message", "")
            if user_id not in profiles:
                return json_response(self, {"error": "Please create a learner profile first"})
            response = (
                f"AI Sensei (demo): I can help with '{message}'. "
                "Ask for a quick summary, quiz, or study plan."
            )
            return json_response(self, {"response": response, "profile": profiles[user_id]})

        if path == "/match":
            jobs = [
                {"job_id": "job_1", "title": "React Developer", "match": "92%", "location": "Remote"},
                {"job_id": "job_2", "title": "Full Stack Developer", "match": "88%", "location": "Nairobi"},
                {"job_id": "job_3", "title": "Smart Contract Engineer", "match": "85%", "location": "Remote"}
            ]
            return json_response(self, {"jobs": jobs})

        if path == "/skill-recommendations":
            return json_response(self, {
                "recommendations": [
                    {"skill": "TypeScript", "priority": "high"},
                    {"skill": "Node.js", "priority": "medium"},
                    {"skill": "System Design", "priority": "medium"}
                ]
            })

        if path == "/verify":
            return json_response(self, {"success": True, "status": "verified", "confidence": 97.5})

        return json_response(self, {"error": "Not found"}, status=404)


if __name__ == "__main__":
    server = HTTPServer((HOST, PORT), DemoHandler)
    print(f"Demo server running on http://{HOST}:{PORT}")
    server.serve_forever()
