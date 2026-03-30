from datetime import datetime
from typing import List, Dict, Any

from fastapi import FastAPI, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

app = FastAPI(title="AI Sensei Lite API", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

profiles: Dict[str, Dict[str, Any]] = {}

class ChatRequest(BaseModel):
    user_id: str
    message: str

class ProfileRequest(BaseModel):
    user_id: str
    name: str
    email: str
    learning_style: str
    preferred_language: str = "en"
    learning_goals: List[str] = []

class QuizRequest(BaseModel):
    topic: str
    difficulty: int
    learning_style: str

@app.get("/health")
async def health():
    return {"status": "ok"}

@app.post("/profile")
async def create_profile(request: ProfileRequest):
    profiles[request.user_id] = {
        "user_id": request.user_id,
        "name": request.name,
        "email": request.email,
        "skill_graph": {"React": 4, "Node": 3, "Solidity": 2},
        "learning_style": request.learning_style,
        "preferred_language": request.preferred_language,
        "total_omni_earned": 420,
        "modules_completed": 12,
        "current_streak": 6,
        "weak_areas": ["Testing"],
        "strong_areas": ["React"],
        "learning_goals": request.learning_goals,
        "created_at": datetime.utcnow().isoformat(),
        "last_active": datetime.utcnow().isoformat(),
    }
    return {"message": "Profile created successfully"}

@app.get("/profile/{user_id}")
async def get_profile(user_id: str):
    profile = profiles.get(user_id)
    if not profile:
        return {"error": "Profile not found"}
    return profile

@app.post("/chat")
async def chat(request: ChatRequest):
    profile = profiles.get(request.user_id)
    if not profile:
        return {"error": "Please create a learner profile first"}
    response = (
        f"AI Sensei (lite): I can help with '{request.message}'. "
        "Try asking for a quick summary or quiz."
    )
    return {"response": response, "profile": profile}

@app.get("/recommendations/{user_id}")
async def get_recommendations(user_id: str, limit: int = 5):
    modules = [
        {"module_id": "react_state", "title": "React State Basics", "omni_reward": 15},
        {"module_id": "node_api", "title": "Build an API with Node", "omni_reward": 20},
        {"module_id": "solidity_intro", "title": "Solidity Intro", "omni_reward": 18},
    ]
    return modules[:limit]

@app.post("/quiz")
async def generate_quiz(request: QuizRequest):
    return {
        "topic": request.topic,
        "question": "What does useState manage in React?",
        "options": ["Routing", "State", "Styling", "Authentication"],
        "correct_answer": "State",
        "explanation": "useState stores component state."
    }

@app.get("/progress/{user_id}")
async def analyze_progress(user_id: str):
    return {
        "user_id": user_id,
        "modules_completed": 12,
        "projects_completed": 3,
        "current_streak": 6,
        "total_omni_earned": 420
    }

@app.post("/voice")
async def process_voice(audio: UploadFile = File(...)):
    return {"transcription": "Demo transcription from voice input."}

@app.get("/learning-path/{user_id}")
async def create_learning_path(user_id: str, goal: str):
    return {
        "goal": goal,
        "path": [
            {"title": "React Fundamentals", "duration_weeks": 3},
            {"title": "Node.js APIs", "duration_weeks": 3},
            {"title": "Deployment Basics", "duration_weeks": 2},
        ]
    }

@app.get("/assessment/{user_id}/{skill}")
async def get_assessment(user_id: str, skill: str):
    return {
        "skill": skill,
        "current_level": 3,
        "target_level": 4,
        "questions": [
            {
                "question": f"What is a core concept in {skill}?",
                "options": ["State", "Routing", "Compression", "Indexing"],
                "correct_answer": "State",
                "explanation": "Core concepts focus on state and data flow."
            }
        ]
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
