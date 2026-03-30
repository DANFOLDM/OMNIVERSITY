"""
Opportunity Radar - AI-powered job matching for The Omniversity Protocol
Scans job markets and matches learners with opportunities based on their skills
"""

import os
import json
import asyncio
import aiohttp
from typing import List, Dict, Optional, Any
from datetime import datetime, timedelta
from dataclasses import dataclass, asdict
from enum import Enum

# Web scraping
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.chrome.options import Options
from bs4 import BeautifulSoup

# AI/ML
from langchain.chat_models import ChatOpenAI
from langchain.embeddings import OpenAIEmbeddings
from langchain.vectorstores import Chroma
from langchain.prompts import PromptTemplate
from langchain.chains import LLMChain

# Database
from sqlalchemy import create_engine, Column, String, Integer, Float, DateTime, JSON, Boolean, Text
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker

Base = declarative_base()

class JobType(Enum):
    FULL_TIME = "full_time"
    PART_TIME = "part_time"
    CONTRACT = "contract"
    FREELANCE = "freelance"
    INTERNSHIP = "internship"
    REMOTE = "remote"

class ExperienceLevel(Enum):
    ENTRY = "entry"
    JUNIOR = "junior"
    MID = "mid"
    SENIOR = "senior"
    LEAD = "lead"
    EXECUTIVE = "executive"

@dataclass
class JobOpportunity:
    """Job opportunity structure"""
    job_id: str
    title: str
    company: str
    location: str
    job_type: JobType
    experience_level: ExperienceLevel
    salary_min: Optional[float]
    salary_max: Optional[float]
    currency: str
    required_skills: List[str]
    preferred_skills: List[str]
    description: str
    requirements: List[str]
    benefits: List[str]
    application_url: str
    source: str
    posted_date: datetime
    deadline: Optional[datetime]
    remote_allowed: bool
    match_score: float  # 0-100
    omni_reward_potential: float

@dataclass
class SkillDemand:
    """Skill demand analysis"""
    skill: str
    demand_score: float  # 0-100
    average_salary: float
    job_count: int
    growth_rate: float  # percentage
    top_companies: List[str]
    related_skills: List[str]

@dataclass
class MarketInsight:
    """Market insight data"""
    region: str
    top_skills: List[SkillDemand]
    average_salary: float
    job_growth: float
    remote_percentage: float
    top_industries: List[str]
    timestamp: datetime

class JobDB(Base):
    """Database model for job opportunities"""
    __tablename__ = 'job_opportunities'
    
    job_id = Column(String, primary_key=True)
    title = Column(String)
    company = Column(String)
    location = Column(String)
    job_type = Column(String)
    experience_level = Column(String)
    salary_min = Column(Float)
    salary_max = Column(Float)
    currency = Column(String)
    required_skills = Column(JSON)
    preferred_skills = Column(JSON)
    description = Column(Text)
    requirements = Column(JSON)
    benefits = Column(JSON)
    application_url = Column(String)
    source = Column(String)
    posted_date = Column(DateTime)
    deadline = Column(DateTime)
    remote_allowed = Column(Boolean)
    match_score = Column(Float)
    omni_reward_potential = Column(Float)
    created_at = Column(DateTime)

class SkillDemandDB(Base):
    """Database model for skill demand"""
    __tablename__ = 'skill_demand'
    
    skill = Column(String, primary_key=True)
    demand_score = Column(Float)
    average_salary = Column(Float)
    job_count = Column(Integer)
    growth_rate = Column(Float)
    top_companies = Column(JSON)
    related_skills = Column(JSON)
    updated_at = Column(DateTime)

class OpportunityRadar:
    """
    AI-powered job matching and market analysis
    Scans multiple job boards and matches learners with opportunities
    """
    
    def __init__(self, openai_api_key: str, db_url: str = "sqlite:///omniversity.db"):
        """Initialize Opportunity Radar"""
        
        # Initialize LLM
        self.llm = ChatOpenAI(
            model="gpt-4",
            temperature=0.3,
            openai_api_key=openai_api_key
        )
        
        # Initialize embeddings
        self.embeddings = OpenAIEmbeddings(openai_api_key=openai_api_key)
        
        # Initialize vector store for job matching
        self.vector_store = Chroma(
            embedding_function=self.embeddings,
            persist_directory="./job_chroma_db"
        )
        
        # Initialize database
        self.engine = create_engine(db_url)
        Base.metadata.create_all(self.engine)
        Session = sessionmaker(bind=self.engine)
        self.db_session = Session()
        
        # Job sources
        self.job_sources = {
            "gomycode": "https://gomycode.com/jobs",
            "linkedin": "https://linkedin.com/jobs",
            "indeed": "https://indeed.com",
            "upwork": "https://upwork.com",
            "freelancer": "https://freelancer.com",
            "remoteok": "https://remoteok.com",
            "weworkremotely": "https://weworkremotely.com"
        }
        
        # Initialize prompts
        self._initialize_prompts()
    
    def _initialize_prompts(self):
        """Initialize prompt templates"""
        
        # Job matching prompt
        self.matching_prompt = PromptTemplate(
            input_variables=["learner_profile", "job_description"],
            template="""Analyze the match between a learner and a job opportunity.

Learner Profile:
{learner_profile}

Job Description:
{job_description}

Provide a match analysis with:
1. Match score (0-100)
2. Matching skills
3. Skill gaps
4. Recommendations for improvement
5. Estimated time to be ready
6. OMNI reward potential (based on skill level)

Format as JSON:
{
    "match_score": 85,
    "matching_skills": ["Python", "React"],
    "skill_gaps": ["AWS", "Docker"],
    "recommendations": ["Complete AWS certification"],
    "estimated_time_weeks": 8,
    "omni_reward_potential": 500
}"""
        )
        
        # Skill demand analysis prompt
        self.demand_prompt = PromptTemplate(
            input_variables=["skill", "job_listings"],
            template="""Analyze the demand for a skill based on job listings.

Skill: {skill}

Job Listings:
{job_listings}

Provide:
1. Demand score (0-100)
2. Average salary
3. Job count
4. Growth rate (percentage)
5. Top hiring companies
6. Related skills

Format as JSON."""
        )
        
        # Market insight prompt
        self.insight_prompt = PromptTemplate(
            input_variables=["region", "job_data"],
            template="""Generate market insights for a region.

Region: {region}

Job Data:
{job_data}

Provide:
1. Top 10 in-demand skills
2. Average salary
3. Job growth rate
4. Remote work percentage
5. Top industries
6. Salary trends

Format as JSON."""
        )
    
    async def scan_jobs(self, source: str = "all", skills: List[str] = None) -> List[JobOpportunity]:
        """Scan job sources for opportunities"""
        jobs = []
        
        if source == "all":
            sources = self.job_sources.keys()
        else:
            sources = [source]
        
        for src in sources:
            try:
                if src == "gomycode":
                    jobs.extend(await self._scan_gomycode(skills))
                elif src == "linkedin":
                    jobs.extend(await self._scan_linkedin(skills))
                elif src == "remoteok":
                    jobs.extend(await self._scan_remoteok(skills))
                # Add more sources as needed
            except Exception as e:
                print(f"Error scanning {src}: {e}")
        
        # Store jobs in database
        for job in jobs:
            self._store_job(job)
        
        return jobs
    
    async def _scan_gomycode(self, skills: List[str] = None) -> List[JobOpportunity]:
        """Scan GoMyCode job board"""
        jobs = []
        
        # In production, implement actual scraping
        # For now, return sample data
        sample_jobs = [
            JobOpportunity(
                job_id="gomycode_001",
                title="Junior Full Stack Developer",
                company="TechStartup Africa",
                location="Lagos, Nigeria",
                job_type=JobType.FULL_TIME,
                experience_level=ExperienceLevel.JUNIOR,
                salary_min=2000,
                salary_max=4000,
                currency="USD",
                required_skills=["JavaScript", "React", "Node.js", "MongoDB"],
                preferred_skills=["TypeScript", "AWS", "Docker"],
                description="Join our growing team to build innovative web applications...",
                requirements=["1+ years experience", "Strong problem-solving skills"],
                benefits=["Health insurance", "Remote work", "Learning budget"],
                application_url="https://gomycode.com/jobs/001",
                source="gomycode",
                posted_date=datetime.utcnow(),
                deadline=datetime.utcnow() + timedelta(days=30),
                remote_allowed=True,
                match_score=0,
                omni_reward_potential=0
            )
        ]
        
        return sample_jobs
    
    async def _scan_linkedin(self, skills: List[str] = None) -> List[JobOpportunity]:
        """Scan LinkedIn jobs"""
        # Implement LinkedIn scraping with Selenium
        return []
    
    async def _scan_remoteok(self, skills: List[str] = None) -> List[JobOpportunity]:
        """Scan RemoteOK API"""
        jobs = []
        
        try:
            async with aiohttp.ClientSession() as session:
                async with session.get("https://remoteok.com/api") as response:
                    if response.status == 200:
                        data = await response.json()
                        
                        for item in data[:50]:  # Limit to 50 jobs
                            job = JobOpportunity(
                                job_id=f"remoteok_{item.get('id', '')}",
                                title=item.get('position', ''),
                                company=item.get('company', ''),
                                location=item.get('location', 'Remote'),
                                job_type=JobType.REMOTE,
                                experience_level=ExperienceLevel.MID,
                                salary_min=item.get('salary_min'),
                                salary_max=item.get('salary_max'),
                                currency="USD",
                                required_skills=item.get('tags', []),
                                preferred_skills=[],
                                description=item.get('description', ''),
                                requirements=[],
                                benefits=[],
                                application_url=item.get('url', ''),
                                source="remoteok",
                                posted_date=datetime.fromisoformat(item.get('date', datetime.utcnow().isoformat())),
                                deadline=None,
                                remote_allowed=True,
                                match_score=0,
                                omni_reward_potential=0
                            )
                            jobs.append(job)
        except Exception as e:
            print(f"Error scanning RemoteOK: {e}")
        
        return jobs
    
    def _store_job(self, job: JobOpportunity):
        """Store job in database"""
        existing = self.db_session.query(JobDB).filter_by(job_id=job.job_id).first()
        
        if not existing:
            job_db = JobDB(
                job_id=job.job_id,
                title=job.title,
                company=job.company,
                location=job.location,
                job_type=job.job_type.value,
                experience_level=job.experience_level.value,
                salary_min=job.salary_min,
                salary_max=job.salary_max,
                currency=job.currency,
                required_skills=job.required_skills,
                preferred_skills=job.preferred_skills,
                description=job.description,
                requirements=job.requirements,
                benefits=job.benefits,
                application_url=job.application_url,
                source=job.source,
                posted_date=job.posted_date,
                deadline=job.deadline,
                remote_allowed=job.remote_allowed,
                match_score=job.match_score,
                omni_reward_potential=job.omni_reward_potential,
                created_at=datetime.utcnow()
            )
            
            self.db_session.add(job_db)
            self.db_session.commit()
    
    async def match_jobs(self, user_id: str, skill_graph: Dict[str, int], limit: int = 10) -> List[JobOpportunity]:
        """Match jobs to learner's skills"""
        # Get all jobs from database
        jobs = self.db_session.query(JobDB).all()
        
        matched_jobs = []
        
        for job_db in jobs:
            # Calculate match score
            match_result = await self._calculate_match(skill_graph, job_db)
            
            if match_result["match_score"] >= 50:  # Only include good matches
                job = JobOpportunity(
                    job_id=job_db.job_id,
                    title=job_db.title,
                    company=job_db.company,
                    location=job_db.location,
                    job_type=JobType(job_db.job_type),
                    experience_level=ExperienceLevel(job_db.experience_level),
                    salary_min=job_db.salary_min,
                    salary_max=job_db.salary_max,
                    currency=job_db.currency,
                    required_skills=job_db.required_skills,
                    preferred_skills=job_db.preferred_skills,
                    description=job_db.description,
                    requirements=job_db.requirements,
                    benefits=job_db.benefits,
                    application_url=job_db.application_url,
                    source=job_db.source,
                    posted_date=job_db.posted_date,
                    deadline=job_db.deadline,
                    remote_allowed=job_db.remote_allowed,
                    match_score=match_result["match_score"],
                    omni_reward_potential=match_result["omni_reward_potential"]
                )
                matched_jobs.append(job)
        
        # Sort by match score
        matched_jobs.sort(key=lambda x: x.match_score, reverse=True)
        
        return matched_jobs[:limit]
    
    async def _calculate_match(self, skill_graph: Dict[str, int], job: JobDB) -> Dict[str, Any]:
        """Calculate match score between skills and job"""
        chain = LLMChain(llm=self.llm, prompt=self.matching_prompt)
        
        response = await chain.arun(
            learner_profile=json.dumps(skill_graph),
            job_description=f"{job.title}\n{job.description}\nRequired: {job.required_skills}"
        )
        
        try:
            return json.loads(response)
        except json.JSONDecodeError:
            # Fallback calculation
            matching_skills = []
            for skill in job.required_skills:
                if skill.lower() in [s.lower() for s in skill_graph.keys()]:
                    matching_skills.append(skill)
            
            match_score = (len(matching_skills) / max(len(job.required_skills), 1)) * 100
            
            return {
                "match_score": match_score,
                "matching_skills": matching_skills,
                "skill_gobbies": [s for s in job.required_skills if s not in matching_skills],
                "recommendations": [],
                "estimated_time_weeks": 4,
                "omni_reward_potential": match_score * 5
            }
    
    async def analyze_skill_demand(self, skill: str, region: str = "Africa") -> SkillDemand:
        """Analyze demand for a specific skill"""
        # Get jobs requiring this skill
        jobs = self.db_session.query(JobDB).filter(
            JobDB.required_skills.contains([skill])
        ).all()
        
        # Calculate metrics
        job_count = len(jobs)
        salaries = [j.salary_min for j in jobs if j.salary_min]
        avg_salary = sum(salaries) / len(salaries) if salaries else 0
        
        # Get top companies
        companies = [j.company for j in jobs]
        top_companies = list(set(companies))[:10]
        
        # Use LLM to analyze
        chain = LLMChain(llm=self.llm, prompt=self.demand_prompt)
        
        response = await chain.arun(
            skill=skill,
            job_listings=json.dumps([{
                "title": j.title,
                "company": j.company,
                "salary": j.salary_min
            } for j in jobs[:20]])
        )
        
        try:
            analysis = json.loads(response)
        except json.JSONDecodeError:
            analysis = {
                "demand_score": min(job_count * 10, 100),
                "average_salary": avg_salary,
                "job_count": job_count,
                "growth_rate": 15.0,
                "top_companies": top_companies,
                "related_skills": []
            }
        
        # Store in database
        skill_demand = SkillDemandDB(
            skill=skill,
            demand_score=analysis.get("demand_score", 0),
            average_salary=analysis.get("average_salary", 0),
            job_count=job_count,
            growth_rate=analysis.get("growth_rate", 0),
            top_companies=analysis.get("top_companies", []),
            related_skills=analysis.get("related_skills", []),
            updated_at=datetime.utcnow()
        )
        
        existing = self.db_session.query(SkillDemandDB).filter_by(skill=skill).first()
        if existing:
            existing.demand_score = skill_demand.demand_score
            existing.average_salary = skill_demand.average_salary
            existing.job_count = skill_demand.job_count
            existing.growth_rate = skill_demand.growth_rate
            existing.top_companies = skill_demand.top_companies
            existing.related_skills = skill_demand.related_skills
            existing.updated_at = skill_demand.updated_at
        else:
            self.db_session.add(skill_demand)
        
        self.db_session.commit()
        
        return SkillDemand(
            skill=skill,
            demand_score=analysis.get("demand_score", 0),
            average_salary=analysis.get("average_salary", 0),
            job_count=job_count,
            growth_rate=analysis.get("growth_rate", 0),
            top_companies=analysis.get("top_companies", []),
            related_skills=analysis.get("related_skills", [])
        )
    
    async def get_market_insights(self, region: str = "Africa") -> MarketInsight:
        """Get market insights for a region"""
        # Get all jobs in region
        jobs = self.db_session.query(JobDB).filter(
            JobDB.location.contains(region)
        ).all()
        
        # Analyze skills
        skill_counts = {}
        for job in jobs:
            for skill in job.required_skills:
                skill_counts[skill] = skill_counts.get(skill, 0) + 1
        
        # Get top skills
        top_skills = []
        for skill, count in sorted(skill_counts.items(), key=lambda x: x[1], reverse=True)[:10]:
            demand = await self.analyze_skill_demand(skill, region)
            top_skills.append(demand)
        
        # Calculate metrics
        salaries = [j.salary_min for j in jobs if j.salary_min]
        avg_salary = sum(salaries) / len(salaries) if salaries else 0
        
        remote_count = sum(1 for j in jobs if j.remote_allowed)
        remote_percentage = (remote_count / len(jobs)) * 100 if jobs else 0
        
        # Use LLM for insights
        chain = LLMChain(llm=self.llm, prompt=self.insight_prompt)
        
        response = await chain.arun(
            region=region,
            job_data=json.dumps({
                "total_jobs": len(jobs),
                "avg_salary": avg_salary,
                "remote_percentage": remote_percentage,
                "top_skills": [s.skill for s in top_skills]
            })
        )
        
        try:
            insights = json.loads(response)
        except json.JSONDecodeError:
            insights = {
                "job_growth": 15.0,
                "top_industries": ["Technology", "Finance", "Healthcare"]
            }
        
        return MarketInsight(
            region=region,
            top_skills=top_skills,
            average_salary=avg_salary,
            job_growth=insights.get("job_growth", 0),
            remote_percentage=remote_percentage,
            top_industries=insights.get("top_industries", []),
            timestamp=datetime.utcnow()
        )
    
    async def get_skill_recommendations(self, skill_graph: Dict[str, int], target_role: str) -> List[Dict[str, Any]]:
        """Get skill recommendations for a target role"""
        # Find jobs matching target role
        jobs = self.db_session.query(JobDB).filter(
            JobDB.title.contains(target_role)
        ).all()
        
        # Analyze required skills
        required_skills = {}
        for job in jobs:
            for skill in job.required_skills:
                required_skills[skill] = required_skills.get(skill, 0) + 1
        
        # Identify gaps
        recommendations = []
        for skill, count in sorted(required_skills.items(), key=lambda x: x[1], reverse=True):
            if skill not in skill_graph:
                recommendations.append({
                    "skill": skill,
                    "priority": "high",
                    "job_demand": count,
                    "estimated_learning_time_weeks": 8,
                    "omni_reward_potential": 100
                })
            elif skill_graph[skill] < 7:  # Below advanced level
                recommendations.append({
                    "skill": skill,
                    "priority": "medium",
                    "current_level": skill_graph[skill],
                    "target_level": 8,
                    "job_demand": count,
                    "estimated_learning_time_weeks": 4,
                    "omni_reward_potential": 50
                })
        
        return recommendations

# FastAPI endpoints
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

app = FastAPI(title="Opportunity Radar API", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Initialize radar
radar = OpportunityRadar(
    openai_api_key=os.getenv("OPENAI_API_KEY"),
    db_url=os.getenv("DATABASE_URL", "sqlite:///omniversity.db")
)

class MatchRequest(BaseModel):
    user_id: str
    skill_graph: Dict[str, int]
    limit: int = 10

class SkillAnalysisRequest(BaseModel):
    skill: str
    region: str = "Africa"

@app.post("/scan")
async def scan_jobs(source: str = "all", skills: List[str] = None):
    """Scan job sources"""
    jobs = await radar.scan_jobs(source, skills)
    return {"jobs": [asdict(j) for j in jobs]}

@app.get("/health")
async def health():
    return {"status": "ok"}

@app.post("/match")
async def match_jobs(request: MatchRequest):
    """Match jobs to learner skills"""
    jobs = await radar.match_jobs(request.user_id, request.skill_graph, request.limit)
    return {"jobs": [asdict(j) for j in jobs]}

@app.post("/skill-demand")
async def analyze_skill_demand(request: SkillAnalysisRequest):
    """Analyze skill demand"""
    demand = await radar.analyze_skill_demand(request.skill, request.region)
    return asdict(demand)

@app.get("/market-insights/{region}")
async def get_market_insights(region: str = "Africa"):
    """Get market insights"""
    insights = await radar.get_market_insights(region)
    return asdict(insights)

@app.post("/skill-recommendations")
async def get_skill_recommendations(skill_graph: Dict[str, int], target_role: str):
    """Get skill recommendations"""
    recommendations = await radar.get_skill_recommendations(skill_graph, target_role)
    return {"recommendations": recommendations}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8001)
