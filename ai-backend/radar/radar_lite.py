from datetime import datetime
from typing import Dict, List

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

app = FastAPI(title="Opportunity Radar Lite API", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

class MatchRequest(BaseModel):
    user_id: str
    skill_graph: Dict[str, int]
    limit: int = 5

class SkillAnalysisRequest(BaseModel):
    skill: str
    region: str = "Africa"

@app.get("/health")
async def health():
    return {"status": "ok"}

@app.post("/scan")
async def scan_jobs(source: str = "all", skills: List[str] = None):
    return {
        "jobs": [
            {"job_id": "job_1", "title": "React Developer", "company": "TechStartup", "location": "Remote"},
            {"job_id": "job_2", "title": "Blockchain Engineer", "company": "DeFi Labs", "location": "Nairobi"}
        ]
    }

@app.post("/match")
async def match_jobs(request: MatchRequest):
    jobs = [
        {"job_id": "job_1", "title": "React Developer", "match": "92%", "location": "Remote"},
        {"job_id": "job_2", "title": "Full Stack Developer", "match": "88%", "location": "Nairobi"},
        {"job_id": "job_3", "title": "Smart Contract Engineer", "match": "85%", "location": "Remote"}
    ]
    return {"jobs": jobs[: request.limit]}

@app.post("/skill-demand")
async def analyze_skill_demand(request: SkillAnalysisRequest):
    return {
        "skill": request.skill,
        "region": request.region,
        "demand_level": "high",
        "trend": "rising",
        "timestamp": datetime.utcnow().isoformat()
    }

@app.get("/market-insights/{region}")
async def get_market_insights(region: str = "Africa"):
    return {
        "region": region,
        "top_roles": ["React Developer", "Data Analyst", "Blockchain Engineer"],
        "timestamp": datetime.utcnow().isoformat()
    }

@app.post("/skill-recommendations")
async def get_skill_recommendations(skill_graph: Dict[str, int], target_role: str):
    return {
        "recommendations": [
            {"skill": "TypeScript", "priority": "high"},
            {"skill": "Node.js", "priority": "medium"},
            {"skill": "System Design", "priority": "medium"}
        ]
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8001)
