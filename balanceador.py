from collections import Counter

from fastapi import FastAPI, HTTPException
import httpx 
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI(
    title= "API DE LA RED DE SERVIDORES",
    description= "Sistema de distribucion de solicitudes"


)
app.add_middleware(
   CORSMiddleware,
   allow_origins=["*"],
   allow_credentials=False,
   allow_methods=["*"],
   allow_headers=["*"],
)


servidores = [
{
    "nombre": "Servidor 1", 
    "url": "http://127.0.0.1:8001",
    "puerto": 8001
},
{
    "nombre": "Servidor 2", 
    "url": "http://127.0.0.1:8002",
    "puerto": 8002
},
{
    "nombre": "Servidor 3", 
    "url": "http://127.0.0.1:8003",
    "puerto": 8003
}]
    
siguiente = 0

solicitudes_por_servidor = Counter()

@app.get("/")
def inicio() -> dict[str, object]:
    return {
        "Sistema": "Red de Servidores dinamica",
        "servidores_configurados": len(servidores),
        "Solicitudes_envidadas": sum(solicitudes_por_servidor.values()),
        "mensaje": "El API esta funcionando correctamente" 
    }

@app.get("/servidores")
async def consultar_servidores() -> dict[str, object]:
    resultados = []
    async with httpx.AsyncClient(timeout=2.0) as client:
        for servidor in servidores:
            estado = "Inactivo"

            try:
                respuesta = await client.get(
                    url = servidor["url"] + "/health"
                )
                if respuesta.status_code == 200:
                    estado = "Activo"

            except httpx.RequestError:
                estado = "Inactivo"    
            resultados.append({
                "nombre": servidor["nombre"],
                "url": servidor["url"],
                "puerto": servidor["puerto"],
                "estado": estado
            })   
    return{
        "total_servidores": len(servidores),
        "servidores": resultados
    }
@app.get("/solicitar")
async def solicitar() -> dict[str, object]:
    global siguiente


    async with httpx.AsyncClient(timeout=2.0) as client: 
        cantidad = len(servidores)

        for _ in range(cantidad):
            servidor = servidores [siguiente % cantidad]
            siguiente= (siguiente + 1) % cantidad

            try:
                salud = await client.get(
                    servidor["url"] + "/health"
                )
                if salud.status_code != 200:
                    continue
                respuesta = await client.get(
                    servidor["url"] + "/procesar"
                )
                if respuesta.status_code == 200:
                    datos = respuesta.json()
                    solicitudes_por_servidor[datos["servidor"]] += 1
                    return datos

            except httpx.RequestError:     
                continue 

    raise HTTPException(
        status_code=503,
        detail="No hay servidores disponibles"
    )


@app.get("/estadisticas")
def estadisticas() -> dict[str, object]:
    return {
        "total_solicitudes": sum(solicitudes_por_servidor.values()),
        "Solicitudes_por_servidor": dict(solicitudes_por_servidor)

    }