"""
AI Sensei - Personalized Learning Mentor for The Omniversity Protocol
Uses LangChain and Whisper for intelligent, adaptive learning experiences
"""

import os
import json
import asyncio
from typing import List, Dict, Optional, Any
from datetime import datetime
from dataclasses import dataclass, asdict
from enum import Enum

# LangChain imports
from langchain.chat_models import ChatOpenAI
from langchain.embeddings import OpenAIEmbeddings
from langchain.vectorstores import Chroma
from langchain.text_splitter import RecursiveCharacterTextSplitter
from langchain.chains import ConversationalRetrievalChain, LLMChain
from langchain.prompts import PromptTemplate, ChatPromptTemplate
from langchain.memory import ConversationBufferWindowMemory
from langchain.schema import Document
from langchain.agents import Tool, AgentExecutor, create_react_agent

# Whisper for voice
import whisper
import torch

# Database
from sqlalchemy import create_engine, Column, String, Integer, Float, DateTime, JSON, Boolean
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker

Base = declarative_base()

class SkillLevel(Enum):
    BEGINNER = 1
    ELEMENTARY = 2
    INTERMEDIATE = 3
    UPPER_INTERMEDIATE = 4
    ADVANCED = 5
    EXPERT = 6
    MASTER = 7
    GRANDMASTER = 8
    LEGENDARY = 9
    MYTHICAL = 10

@dataclass
class LearnerProfile:
    """Learner profile with skill tracking"""
    user_id: str
    name: str
    email: str
    skill_graph: Dict[str, int]  # skill -> level (1-10)
    learning_style: str  # visual, auditory, kinesthetic, reading
    preferred_language: str
    total_omni_earned: float
    modules_completed: int
    current_streak: int
    weak_areas: List[str]
    strong_areas: List[str]
    learning_goals: List[str]
    created_at: datetime
    last_active: datetime

@dataclass
class LearningModule:
    """Learning module structure"""
    module_id: str
    title: str
    description: str
    skill_category: str
    difficulty_level: int
    estimated_duration: int  # minutes
    prerequisites: List[str]
    content: Dict[str, Any]  # lessons, exercises, projects
    omni_reward: int
    created_at: datetime

@dataclass
class LearningSession:
    """Individual learning session"""
    session_id: str
    user_id: str
    module_id: str
    start_time: datetime
    end_time: Optional[datetime]
    progress: float  # 0-100
    interactions: List[Dict[str, Any]]
    quiz_scores: List[float]
    omni_earned: float
    feedback: Optional[str]

class LearnerProfileDB(Base):
    """Database model for learner profiles"""
    __tablename__ = 'learner_profiles'
    
    user_id = Column(String, primary_key=True)
    name = Column(String)
    email = Column(String)
    skill_graph = Column(JSON)
    learning_style = Column(String)
    preferred_language = Column(String)
    total_omni_earned = Column(Float, default=0)
    modules_completed = Column(Integer, default=0)
    current_streak = Column(Integer, default=0)
    weak_areas = Column(JSON)
    strong_areas = Column(JSON)
    learning_goals = Column(JSON)
    created_at = Column(DateTime)
    last_active = Column(DateTime)

class LearningModuleDB(Base):
    """Database model for learning modules"""
    __tablename__ = 'learning_modules'
    
    module_id = Column(String, primary_key=True)
    title = Column(String)
    description = Column(String)
    skill_category = Column(String)
    difficulty_level = Column(Integer)
    estimated_duration = Column(Integer)
    prerequisites = Column(JSON)
    content = Column(JSON)
    omni_reward = Column(Integer)
    created_at = Column(DateTime)

class AISensei:
    """
    AI-powered personalized learning mentor
    Provides adaptive learning paths, instant feedback, and voice interaction
    """
    
    def __init__(self, openai_api_key: str, db_url: str = "sqlite:///omniversity.db"):
        """Initialize AI Sensei with LLM and database"""
        
        # Initialize LLM
        self.llm = ChatOpenAI(
            model="gpt-4",
            temperature=0.7,
            openai_api_key=openai_api_key
        )
        
        # Initialize embeddings
        self.embeddings = OpenAIEmbeddings(openai_api_key=openai_api_key)
        
        # Initialize vector store for curriculum
        self.vector_store = Chroma(
            embedding_function=self.embeddings,
            persist_directory="./chroma_db"
        )
        
        # Initialize Whisper for voice
        self.whisper_model = whisper.load_model("base")
        
        # Initialize database
        self.engine = create_engine(db_url)
        Base.metadata.create_all(self.engine)
        Session = sessionmaker(bind=self.engine)
        self.db_session = Session()
        
        # Initialize conversation memory
        self.memory = ConversationBufferWindowMemory(
            memory_key="chat_history",
            return_messages=True,
            k=10
        )
        
        # Initialize prompts
        self._initialize_prompts()
        
        # Initialize tools
        self._initialize_tools()
        
        # Initialize agent
        self._initialize_agent()
    
    def _initialize_prompts(self):
        """Initialize prompt templates"""
        
        # Main teaching prompt
        self.teaching_prompt = ChatPromptTemplate.from_messages([
            ("system", """You are AI Sensei, a personalized learning mentor for The Omniversity Protocol.
            
Your role:
- Adapt teaching style to each learner's preferences
- Provide clear, concise explanations
- Use real-world examples and analogies
- Encourage and motivate learners
- Track progress and suggest improvements
- Award OMNI tokens for achievements

Learner Profile:
{learner_profile}

Current Module:
{current_module}

Learning Style: {learning_style}
Preferred Language: {preferred_language}

Guidelines:
1. Be patient and supportive
2. Break complex topics into smaller chunks
3. Use the Socratic method when appropriate
4. Provide immediate feedback on exercises
5. Suggest related modules based on progress
6. Celebrate achievements and milestones"""),
            ("human", "{input}")
        ])
        
        # Quiz generation prompt
        self.quiz_prompt = PromptTemplate(
            input_variables=["topic", "difficulty", "learning_style"],
            template="""Generate a quiz question about {topic} at difficulty level {difficulty}/10.
            
Learning style: {learning_style}

Format:
{
    "question": "Question text",
    "options": ["A", "B", "C", "D"],
    "correct_answer": "A",
    "explanation": "Why this is correct",
    "hint": "A helpful hint"
}"""
        )
        
        # Progress analysis prompt
        self.progress_prompt = PromptTemplate(
            input_variables=["skill_graph", "recent_activity", "goals"],
            template="""Analyze the learner's progress and provide recommendations:

Skill Graph: {skill_graph}
Recent Activity: {recent_activity}
Learning Goals: {goals}

Provide:
1. Progress summary
2. Strengths identified
3. Areas for improvement
4. Recommended next modules
5. Estimated time to reach next level
6. Motivational message"""
        )
    
    def _initialize_tools(self):
        """Initialize AI tools"""
        
        self.tools = [
            Tool(
                name="get_learner_profile",
                func=self.get_learner_profile,
                description="Get learner profile and skill graph"
            ),
            Tool(
                name="get_recommended_modules",
                func=self.get_recommended_modules,
                description="Get personalized module recommendations"
            ),
            Tool(
                name="generate_quiz",
                func=self.generate_quiz,
                description="Generate a quiz question"
            ),
            Tool(
                name="analyze_progress",
                func=self.analyze_progress,
                description="Analyze learning progress"
            ),
            Tool(
                name="calculate_omni_reward",
                func=self.calculate_omni_reward,
                description="Calculate OMNI token reward"
            ),
            Tool(
                name="update_skill_level",
                func=self.update_skill_level,
                description="Update skill level after completion"
            )
        ]
    
    def _initialize_agent(self):
        """Initialize the AI agent"""
        
        agent_prompt = PromptTemplate(
            input_variables=["input", "agent_scratchpad", "tools", "tool_names"],
            template="""You are AI Sensei, a personalized learning mentor.

Available tools: {tool_names}

Tool descriptions:
{tools}

Use the following format:
Question: the input question you must answer
Thought: you should always think about what to do
Action: the action to take, should be one of [{tool_names}]
Action Input: the input to the action
Observation: the result of the action
... (this Thought/Action/Action Input/Observation can repeat N times)
Thought: I now know the final answer
Final Answer: the final answer to the original input question

Begin!

Question: {input}
Thought: {agent_scratchpad}"""
        )
        
        self.agent = create_react_agent(
            llm=self.llm,
            tools=self.tools,
            prompt=agent_prompt
        )
        
        self.agent_executor = AgentExecutor(
            agent=self.agent,
            tools=self.tools,
            memory=self.memory,
            verbose=True,
            handle_parsing_errors=True
        )
    
    async def get_learner_profile(self, user_id: str) -> Dict[str, Any]:
        """Get learner profile from database"""
        profile = self.db_session.query(LearnerProfileDB).filter_by(user_id=user_id).first()
        
        if profile:
            return {
                "user_id": profile.user_id,
                "name": profile.name,
                "skill_graph": profile.skill_graph,
                "learning_style": profile.learning_style,
                "preferred_language": profile.preferred_language,
                "total_omni_earned": profile.total_omni_earned,
                "modules_completed": profile.modules_completed,
                "current_streak": profile.current_streak,
                "weak_areas": profile.weak_areas,
                "strong_areas": profile.strong_areas,
                "learning_goals": profile.learning_goals
            }
        return {"error": "Profile not found"}
    
    async def get_recommended_modules(self, user_id: str, limit: int = 5) -> List[Dict[str, Any]]:
        """Get personalized module recommendations"""
        profile = await self.get_learner_profile(user_id)
        
        if "error" in profile:
            return []
        
        # Get all modules
        modules = self.db_session.query(LearningModuleDB).all()
        
        # Score modules based on learner profile
        scored_modules = []
        for module in modules:
            score = self._calculate_module_score(module, profile)
            scored_modules.append({
                "module_id": module.module_id,
                "title": module.title,
                "description": module.description,
                "skill_category": module.skill_category,
                "difficulty_level": module.difficulty_level,
                "omni_reward": module.omni_reward,
                "score": score
            })
        
        # Sort by score and return top recommendations
        scored_modules.sort(key=lambda x: x["score"], reverse=True)
        return scored_modules[:limit]
    
    def _calculate_module_score(self, module: LearningModuleDB, profile: Dict[str, Any]) -> float:
        """Calculate recommendation score for a module"""
        score = 0.0
        
        # Skill match
        if module.skill_category in profile["skill_graph"]:
            current_level = profile["skill_graph"][module.skill_category]
            # Prefer modules slightly above current level
            if module.difficulty_level == current_level + 1:
                score += 50
            elif module.difficulty_level == current_level:
                score += 30
            elif module.difficulty_level > current_level + 2:
                score -= 20
        
        # Weak area focus
        if module.skill_category in profile["weak_areas"]:
            score += 40
        
        # Learning style match
        content = module.content or {}
        if profile["learning_style"] == "visual" and "videos" in content:
            score += 20
        elif profile["learning_style"] == "kinesthetic" and "projects" in content:
            score += 20
        elif profile["learning_style"] == "reading" and "articles" in content:
            score += 20
        
        # OMNI reward attractiveness
        score += min(module.omni_reward / 10, 20)
        
        return score
    
    async def generate_quiz(self, topic: str, difficulty: int, learning_style: str) -> Dict[str, Any]:
        """Generate a quiz question"""
        chain = LLMChain(llm=self.llm, prompt=self.quiz_prompt)
        
        response = await chain.arun(
            topic=topic,
            difficulty=difficulty,
            learning_style=learning_style
        )
        
        try:
            return json.loads(response)
        except json.JSONDecodeError:
            return {
                "question": f"What is a key concept in {topic}?",
                "options": ["Option A", "Option B", "Option C", "Option D"],
                "correct_answer": "Option A",
                "explanation": "This is the correct answer because...",
                "hint": "Think about the fundamentals"
            }
    
    async def analyze_progress(self, user_id: str) -> Dict[str, Any]:
        """Analyze learner progress and provide recommendations"""
        profile = await self.get_learner_profile(user_id)
        
        if "error" in profile:
            return profile
        
        chain = LLMChain(llm=self.llm, prompt=self.progress_prompt)
        
        response = await chain.arun(
            skill_graph=json.dumps(profile["skill_graph"]),
            recent_activity=f"Modules completed: {profile['modules_completed']}, Streak: {profile['current_streak']}",
            goals=json.dumps(profile["learning_goals"])
        )
        
        return {
            "analysis": response,
            "profile": profile
        }
    
    async def calculate_omni_reward(self, activity_type: str, skill_level: int, time_bonus: bool = False) -> float:
        """Calculate OMNI token reward for an activity"""
        base_rewards = {
            "module_completion": 10,
            "project_submission": 50,
            "peer_mentorship": 25,
            "guild_participation": 15,
            "skill_milestone": 100,
            "code_review": 20,
            "forum_contribution": 5,
            "attendance": 8
        }
        
        base = base_rewards.get(activity_type, 10)
        
        # Skill multiplier
        skill_multiplier = 1 + (skill_level * 0.1)
        
        # Time bonus
        time_bonus_amount = 5 if time_bonus else 0
        
        total = (base * skill_multiplier) + time_bonus_amount
        
        return round(total, 2)
    
    async def update_skill_level(self, user_id: str, skill: str, new_level: int) -> bool:
        """Update skill level in database"""
        profile = self.db_session.query(LearnerProfileDB).filter_by(user_id=user_id).first()
        
        if profile:
            skill_graph = profile.skill_graph or {}
            skill_graph[skill] = new_level
            profile.skill_graph = skill_graph
            profile.last_active = datetime.utcnow()
            
            self.db_session.commit()
            return True
        
        return False
    
    async def process_voice_input(self, audio_file_path: str) -> str:
        """Process voice input using Whisper"""
        try:
            result = self.whisper_model.transcribe(audio_file_path)
            return result["text"]
        except Exception as e:
            return f"Error processing voice: {str(e)}"
    
    async def generate_voice_response(self, text: str, output_path: str) -> str:
        """Generate voice response (placeholder for TTS integration)"""
        # In production, integrate with a TTS service like ElevenLabs
        # For now, return the text
        return text
    
    async def chat(self, user_id: str, message: str) -> Dict[str, Any]:
        """Main chat interface with AI Sensei"""
        profile = await self.get_learner_profile(user_id)
        
        if "error" in profile:
            return {"error": "Please create a learner profile first"}
        
        # Prepare context
        context = {
            "learner_profile": json.dumps(profile),
            "current_module": "General Learning",
            "learning_style": profile["learning_style"],
            "preferred_language": profile["preferred_language"],
            "input": message
        }
        
        # Run agent
        response = await self.agent_executor.ainvoke(context)
        
        return {
            "response": response["output"],
            "profile": profile
        }
    
    async def create_learning_path(self, user_id: str, goal: str) -> List[Dict[str, Any]]:
        """Create a personalized learning path"""
        profile = await self.get_learner_profile(user_id)
        
        if "error" in profile:
            return []
        
        # Use LLM to generate learning path
        prompt = f"""Create a personalized learning path for:
Goal: {goal}
Current Skills: {json.dumps(profile['skill_graph'])}
Learning Style: {profile['learning_style']}
Weak Areas: {json.dumps(profile['weak_areas'])}

Generate a sequence of modules with:
1. Module title
2. Skill category
3. Difficulty level
4. Estimated duration
5. Prerequisites
6. OMNI reward

Format as JSON array."""
        
        response = await self.llm.ainvoke(prompt)
        
        try:
            learning_path = json.loads(response.content)
            return learning_path
        except json.JSONDecodeError:
            return []
    
    async def get_skill_assessment(self, user_id: str, skill: str) -> Dict[str, Any]:
        """Assess current skill level"""
        profile = await self.get_learner_profile(user_id)
        
        if "error" in profile:
            return profile
        
        current_level = profile["skill_graph"].get(skill, 0)
        
        # Generate assessment questions
        assessment_prompt = f"""Generate a skill assessment for {skill} at level {current_level + 1}.

Create 5 questions that test:
1. Fundamental concepts
2. Practical application
3. Problem-solving
4. Best practices
5. Advanced concepts

Format as JSON array with question, options, correct_answer, and explanation."""
        
        response = await self.llm.ainvoke(assessment_prompt)
        
        try:
            questions = json.loads(response.content)
            return {
                "skill": skill,
                "current_level": current_level,
                "target_level": current_level + 1,
                "questions": questions
            }
        except json.JSONDecodeError:
            return {
                "skill": skill,
                "current_level": current_level,
                "error": "Failed to generate assessment"
            }

# FastAPI endpoints for the AI Sensei
from fastapi import FastAPI, HTTPException, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

app = FastAPI(title="AI Sensei API", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Initialize AI Sensei
sensei = AISensei(
    openai_api_key=os.getenv("OPENAI_API_KEY"),
    db_url=os.getenv("DATABASE_URL", "sqlite:///omniversity.db")
)

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

@app.post("/chat")
async def chat(request: ChatRequest):
    """Chat with AI Sensei"""
    response = await sensei.chat(request.user_id, request.message)
    return response

@app.get("/health")
async def health():
    return {"status": "ok"}

@app.get("/profile/{user_id}")
async def get_profile(user_id: str):
    """Get learner profile"""
    profile = await sensei.get_learner_profile(user_id)
    return profile

@app.post("/profile")
async def create_profile(request: ProfileRequest):
    """Create learner profile"""
    profile = LearnerProfileDB(
        user_id=request.user_id,
        name=request.name,
        email=request.email,
        skill_graph={},
        learning_style=request.learning_style,
        preferred_language=request.preferred_language,
        total_omni_earned=0,
        modules_completed=0,
        current_streak=0,
        weak_areas=[],
        strong_areas=[],
        learning_goals=request.learning_goals,
        created_at=datetime.utcnow(),
        last_active=datetime.utcnow()
    )
    
    sensei.db_session.add(profile)
    sensei.db_session.commit()
    
    return {"message": "Profile created successfully"}

@app.get("/recommendations/{user_id}")
async def get_recommendations(user_id: str, limit: int = 5):
    """Get module recommendations"""
    recommendations = await sensei.get_recommended_modules(user_id, limit)
    return recommendations

@app.post("/quiz")
async def generate_quiz(request: QuizRequest):
    """Generate a quiz question"""
    quiz = await sensei.generate_quiz(
        request.topic,
        request.difficulty,
        request.learning_style
    )
    return quiz

@app.get("/progress/{user_id}")
async def analyze_progress(user_id: str):
    """Analyze learning progress"""
    analysis = await sensei.analyze_progress(user_id)
    return analysis

@app.post("/voice")
async def process_voice(audio: UploadFile = File(...)):
    """Process voice input"""
    # Save uploaded file
    temp_path = f"/tmp/{audio.filename}"
    with open(temp_path, "wb") as buffer:
        buffer.write(await audio.read())
    
    # Process with Whisper
    text = await sensei.process_voice_input(temp_path)
    
    # Clean up
    os.remove(temp_path)
    
    return {"transcription": text}

@app.get("/learning-path/{user_id}")
async def create_learning_path(user_id: str, goal: str):
    """Create personalized learning path"""
    path = await sensei.create_learning_path(user_id, goal)
    return path

@app.get("/assessment/{user_id}/{skill}")
async def get_assessment(user_id: str, skill: str):
    """Get skill assessment"""
    assessment = await sensei.get_skill_assessment(user_id, skill)
    return assessment

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
