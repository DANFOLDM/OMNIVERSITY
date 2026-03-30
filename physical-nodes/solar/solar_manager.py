"""
Solar Node Manager for The Omniversity Protocol
Manages solar-powered edge computing nodes with energy NFT generation
"""

import os
import json
import asyncio
import logging
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any
from dataclasses import dataclass, asdict

# Database
from sqlalchemy import create_engine, Column, String, Integer, Float, DateTime, JSON, Boolean
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker

# Blockchain
from web3 import Web3
from eth_account import Account

Base = declarative_base()

@dataclass
class SolarNode:
    """Solar-powered node configuration"""
    node_id: str
    location: str
    latitude: float
    longitude: float
    solar_panel_capacity: float  # Watts
    battery_capacity: float  # Wh
    current_battery: float  # Wh
    daily_energy_generated: float  # Wh
    daily_energy_consumed: float  # Wh
    is_online: bool
    last_heartbeat: datetime
    carbon_credits_earned: float
    energy_nfts_minted: int

@dataclass
class EnergyReading:
    """Energy production/consumption reading"""
    reading_id: str
    node_id: str
    timestamp: datetime
    solar_power: float  # Watts
    battery_level: float  # Percentage
    energy_generated: float  # Wh
    energy_consumed: float  # Wh
    temperature: float  # Celsius
    efficiency: float  # Percentage

@dataclass
class CarbonCredit:
    """Carbon credit NFT"""
    credit_id: str
    node_id: str
    energy_amount: float  # Wh
    carbon_offset: float  # kg CO2
    minted_at: datetime
    token_id: str
    verified: bool

class SolarNodeDB(Base):
    """Database model for solar nodes"""
    __tablename__ = 'solar_nodes'
    
    node_id = Column(String, primary_key=True)
    location = Column(String)
    latitude = Column(Float)
    longitude = Column(Float)
    solar_panel_capacity = Column(Float)
    battery_capacity = Column(Float)
    current_battery = Column(Float)
    daily_energy_generated = Column(Float, default=0)
    daily_energy_consumed = Column(Float, default=0)
    is_online = Column(Boolean, default=False)
    last_heartbeat = Column(DateTime)
    carbon_credits_earned = Column(Float, default=0)
    energy_nfts_minted = Column(Integer, default=0)
    created_at = Column(DateTime)

class EnergyReadingDB(Base):
    """Database model for energy readings"""
    __tablename__ = 'energy_readings'
    
    reading_id = Column(String, primary_key=True)
    node_id = Column(String)
    timestamp = Column(DateTime)
    solar_power = Column(Float)
    battery_level = Column(Float)
    energy_generated = Column(Float)
    energy_consumed = Column(Float)
    temperature = Column(Float)
    efficiency = Column(Float)

class CarbonCreditDB(Base):
    """Database model for carbon credits"""
    __tablename__ = 'carbon_credits'
    
    credit_id = Column(String, primary_key=True)
    node_id = Column(String)
    energy_amount = Column(Float)
    carbon_offset = Column(Float)
    minted_at = Column(DateTime)
    token_id = Column(String)
    verified = Column(Boolean, default=False)

class SolarNodeManager:
    """
    Manages solar-powered edge computing nodes
    Handles energy monitoring, carbon credit generation, and NFT minting
    """
    
    def __init__(self, db_url: str = "sqlite:///omniversity.db", rpc_url: str = None):
        """Initialize solar node manager"""
        
        # Initialize database
        self.engine = create_engine(db_url)
        Base.metadata.create_all(self.engine)
        Session = sessionmaker(bind=self.engine)
        self.db_session = Session()
        
        # Initialize Web3
        if rpc_url:
            self.w3 = Web3(Web3.HTTPProvider(rpc_url))
        else:
            self.w3 = None
        
        # Carbon credit calculation constants
        self.CARBON_OFFSET_PER_KWH = 0.5  # kg CO2 per kWh
        self.ENERGY_NFT_THRESHOLD = 1000  # Wh threshold for minting NFT
        
        # Energy efficiency factors
        self.SOLAR_EFFICIENCY = 0.20  # 20% solar panel efficiency
        self.BATTERY_EFFICIENCY = 0.90  # 90% battery efficiency
        self.INVERTER_EFFICIENCY = 0.95  # 95% inverter efficiency
    
    async def register_node(
        self,
        node_id: str,
        location: str,
        latitude: float,
        longitude: float,
        solar_panel_capacity: float,
        battery_capacity: float
    ) -> Dict[str, Any]:
        """Register a new solar node"""
        
        existing = self.db_session.query(SolarNodeDB).filter_by(node_id=node_id).first()
        
        if existing:
            return {"success": False, "error": "Node already registered"}
        
        node = SolarNodeDB(
            node_id=node_id,
            location=location,
            latitude=latitude,
            longitude=longitude,
            solar_panel_capacity=solar_panel_capacity,
            battery_capacity=battery_capacity,
            current_battery=battery_capacity,
            daily_energy_generated=0,
            daily_energy_consumed=0,
            is_online=False,
            last_heartbeat=datetime.utcnow(),
            carbon_credits_earned=0,
            energy_nfts_minted=0,
            created_at=datetime.utcnow()
        )
        
        self.db_session.add(node)
        self.db_session.commit()
        
        return {
            "success": True,
            "node_id": node_id,
            "message": "Node registered successfully"
        }
    
    async def record_energy_reading(
        self,
        node_id: str,
        solar_power: float,
        battery_level: float,
        energy_generated: float,
        energy_consumed: float,
        temperature: float
    ) -> Dict[str, Any]:
        """Record energy production/consumption reading"""
        
        node = self.db_session.query(SolarNodeDB).filter_by(node_id=node_id).first()
        
        if not node:
            return {"success": False, "error": "Node not found"}
        
        # Calculate efficiency
        efficiency = self._calculate_efficiency(
            solar_power,
            energy_generated,
            energy_consumed,
            temperature
        )
        
        # Create reading
        reading_id = f"{node_id}_{datetime.utcnow().strftime('%Y%m%d_%H%M%S')}"
        
        reading = EnergyReadingDB(
            reading_id=reading_id,
            node_id=node_id,
            timestamp=datetime.utcnow(),
            solar_power=solar_power,
            battery_level=battery_level,
            energy_generated=energy_generated,
            energy_consumed=energy_consumed,
            temperature=temperature,
            efficiency=efficiency
        )
        
        self.db_session.add(reading)
        
        # Update node statistics
        node.daily_energy_generated += energy_generated
        node.daily_energy_consumed += energy_consumed
        node.current_battery = (battery_level / 100) * node.battery_capacity
        node.last_heartbeat = datetime.utcnow()
        node.is_online = True
        
        # Check if we should mint energy NFT
        if node.daily_energy_generated >= self.ENERGY_NFT_THRESHOLD:
            await self._mint_energy_nft(node_id, node.daily_energy_generated)
            node.daily_energy_generated = 0  # Reset counter
        
        self.db_session.commit()
        
        return {
            "success": True,
            "reading_id": reading_id,
            "efficiency": efficiency,
            "battery_level": battery_level
        }
    
    def _calculate_efficiency(
        self,
        solar_power: float,
        energy_generated: float,
        energy_consumed: float,
        temperature: float
    ) -> float:
        """Calculate energy efficiency"""
        
        # Temperature derating (efficiency decreases with high temperature)
        temp_factor = 1.0 - max(0, (temperature - 25) * 0.004)
        
        # Overall efficiency
        efficiency = (
            self.SOLAR_EFFICIENCY *
            self.BATTERY_EFFICIENCY *
            self.INVERTER_EFFICIENCY *
            temp_factor *
            100
        )
        
        return min(100, max(0, efficiency))
    
    async def _mint_energy_nft(self, node_id: str, energy_amount: float):
        """Mint energy NFT for carbon credits"""
        
        # Calculate carbon offset
        carbon_offset = (energy_amount / 1000) * self.CARBON_OFFSET_PER_KWH
        
        # Generate credit ID
        credit_id = f"carbon_{node_id}_{datetime.utcnow().strftime('%Y%m%d_%H%M%S')}"
        
        # In production, mint actual NFT on blockchain
        # For now, create database record
        credit = CarbonCreditDB(
            credit_id=credit_id,
            node_id=node_id,
            energy_amount=energy_amount,
            carbon_offset=carbon_offset,
            minted_at=datetime.utcnow(),
            token_id=f"0x{credit_id}",  # Placeholder
            verified=True
        )
        
        self.db_session.add(credit)
        
        # Update node statistics
        node = self.db_session.query(SolarNodeDB).filter_by(node_id=node_id).first()
        if node:
            node.carbon_credits_earned += carbon_offset
            node.energy_nfts_minted += 1
        
        logging.info(f"Minted energy NFT for node {node_id}: {carbon_offset} kg CO2")
    
    async def get_node_status(self, node_id: str) -> Dict[str, Any]:
        """Get node status and statistics"""
        
        node = self.db_session.query(SolarNodeDB).filter_by(node_id=node_id).first()
        
        if not node:
            return {"error": "Node not found"}
        
        # Get recent readings
        recent_readings = self.db_session.query(EnergyReadingDB).filter_by(
            node_id=node_id
        ).order_by(EnergyReadingDB.timestamp.desc()).limit(24).all()
        
        # Calculate statistics
        avg_efficiency = sum(r.efficiency for r in recent_readings) / len(recent_readings) if recent_readings else 0
        
        return {
            "node_id": node.node_id,
            "location": node.location,
            "is_online": node.is_online,
            "last_heartbeat": node.last_heartbeat.isoformat(),
            "solar_panel_capacity": node.solar_panel_capacity,
            "battery_capacity": node.battery_capacity,
            "current_battery": node.current_battery,
            "battery_percentage": (node.current_battery / node.battery_capacity) * 100,
            "daily_energy_generated": node.daily_energy_generated,
            "daily_energy_consumed": node.daily_energy_consumed,
            "net_energy": node.daily_energy_generated - node.daily_energy_consumed,
            "carbon_credits_earned": node.carbon_credits_earned,
            "energy_nfts_minted": node.energy_nfts_minted,
            "average_efficiency": avg_efficiency,
            "readings_count": len(recent_readings)
        }
    
    async def get_all_nodes(self) -> List[Dict[str, Any]]:
        """Get all registered nodes"""
        
        nodes = self.db_session.query(SolarNodeDB).all()
        
        return [
            {
                "node_id": node.node_id,
                "location": node.location,
                "is_online": node.is_online,
                "solar_panel_capacity": node.solar_panel_capacity,
                "current_battery": node.current_battery,
                "carbon_credits_earned": node.carbon_credits_earned,
                "energy_nfts_minted": node.energy_nfts_minted
            }
            for node in nodes
        ]
    
    async def get_carbon_credits(self, node_id: str = None) -> List[Dict[str, Any]]:
        """Get carbon credits"""
        
        query = self.db_session.query(CarbonCreditDB)
        
        if node_id:
            query = query.filter_by(node_id=node_id)
        
        credits = query.order_by(CarbonCreditDB.minted_at.desc()).all()
        
        return [
            {
                "credit_id": credit.credit_id,
                "node_id": credit.node_id,
                "energy_amount": credit.energy_amount,
                "carbon_offset": credit.carbon_offset,
                "minted_at": credit.minted_at.isoformat(),
                "token_id": credit.token_id,
                "verified": credit.verified
            }
            for credit in credits
        ]
    
    async def predict_energy_production(
        self,
        node_id: str,
        hours: int = 24
    ) -> Dict[str, Any]:
        """Predict energy production for next hours"""
        
        node = self.db_session.query(SolarNodeDB).filter_by(node_id=node_id).first()
        
        if not node:
            return {"error": "Node not found"}
        
        # Get historical data
        past_readings = self.db_session.query(EnergyReadingDB).filter_by(
            node_id=node_id
        ).order_by(EnergyReadingDB.timestamp.desc()).limit(168).all()  # 1 week
        
        if not past_readings:
            return {"error": "No historical data"}
        
        # Calculate average hourly production
        total_hours = len(past_readings)
        total_energy = sum(r.energy_generated for r in past_readings)
        avg_hourly_production = total_energy / total_hours if total_hours > 0 else 0
        
        # Predict based on solar capacity and historical efficiency
        avg_efficiency = sum(r.efficiency for r in past_readings) / len(past_readings)
        predicted_production = (
            node.solar_panel_capacity *
            (avg_efficiency / 100) *
            hours
        )
        
        return {
            "node_id": node_id,
            "prediction_hours": hours,
            "predicted_production_wh": predicted_production,
            "average_hourly_production_wh": avg_hourly_production,
            "average_efficiency": avg_efficiency,
            "confidence": min(100, len(past_readings) / 168 * 100)
        }
    
    async def optimize_energy_usage(self, node_id: str) -> Dict[str, Any]:
        """Optimize energy usage for a node"""
        
        node = self.db_session.query(SolarNodeDB).filter_by(node_id=node_id).first()
        
        if not node:
            return {"error": "Node not found"}
        
        # Get recent readings
        recent_readings = self.db_session.query(EnergyReadingDB).filter_by(
            node_id=node_id
        ).order_by(EnergyReadingDB.timestamp.desc()).limit(24).all()
        
        # Analyze patterns
        peak_hours = []
        low_hours = []
        
        for reading in recent_readings:
            hour = reading.timestamp.hour
            if reading.solar_power > node.solar_panel_capacity * 0.7:
                peak_hours.append(hour)
            elif reading.solar_power < node.solar_panel_capacity * 0.3:
                low_hours.append(hour)
        
        # Generate recommendations
        recommendations = []
        
        if node.current_battery < node.battery_capacity * 0.2:
            recommendations.append("Battery low - reduce non-essential loads")
        
        if len(peak_hours) > 0:
            recommendations.append(f"Peak solar hours: {', '.join(map(str, peak_hours))}")
        
        if len(low_hours) > 0:
            recommendations.append(f"Low production hours: {', '.join(map(str, low_hours))}")
        
        return {
            "node_id": node_id,
            "current_battery_percentage": (node.current_battery / node.battery_capacity) * 100,
            "daily_net_energy": node.daily_energy_generated - node.daily_energy_consumed,
            "peak_hours": peak_hours,
            "low_hours": low_hours,
            "recommendations": recommendations
        }

# FastAPI endpoints
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

app = FastAPI(title="Solar Node Manager API", version="1.0.0")

# Initialize manager
manager = SolarNodeManager(
    db_url=os.getenv("DATABASE_URL", "sqlite:///omniversity.db"),
    rpc_url=os.getenv("RPC_URL")
)

class RegisterNodeRequest(BaseModel):
    node_id: str
    location: str
    latitude: float
    longitude: float
    solar_panel_capacity: float
    battery_capacity: float

class EnergyReadingRequest(BaseModel):
    node_id: str
    solar_power: float
    battery_level: float
    energy_generated: float
    energy_consumed: float
    temperature: float

@app.post("/nodes/register")
async def register_node(request: RegisterNodeRequest):
    """Register a new solar node"""
    result = await manager.register_node(
        node_id=request.node_id,
        location=request.location,
        latitude=request.latitude,
        longitude=request.longitude,
        solar_panel_capacity=request.solar_panel_capacity,
        battery_capacity=request.battery_capacity
    )
    return result

@app.post("/nodes/reading")
async def record_reading(request: EnergyReadingRequest):
    """Record energy reading"""
    result = await manager.record_energy_reading(
        node_id=request.node_id,
        solar_power=request.solar_power,
        battery_level=request.battery_level,
        energy_generated=request.energy_generated,
        energy_consumed=request.energy_consumed,
        temperature=request.temperature
    )
    return result

@app.get("/nodes/{node_id}/status")
async def get_node_status(node_id: str):
    """Get node status"""
    status = await manager.get_node_status(node_id)
    return status

@app.get("/nodes")
async def get_all_nodes():
    """Get all nodes"""
    nodes = await manager.get_all_nodes()
    return {"nodes": nodes}

@app.get("/carbon-credits")
async def get_carbon_credits(node_id: str = None):
    """Get carbon credits"""
    credits = await manager.get_carbon_credits(node_id)
    return {"credits": credits}

@app.get("/nodes/{node_id}/predict")
async def predict_energy(node_id: str, hours: int = 24):
    """Predict energy production"""
    prediction = await manager.predict_energy_production(node_id, hours)
    return prediction

@app.get("/nodes/{node_id}/optimize")
async def optimize_energy(node_id: str):
    """Get energy optimization recommendations"""
    optimization = await manager.optimize_energy_usage(node_id)
    return optimization

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8003)
