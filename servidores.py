import argparse
from threading import Lock

from fastapi import FastAPI
import uvicorn

app = FastAPI(
    title="Servidor de la Red Dinamica"
)

puerto = 8001
nombre = "Servidor 1"

contador=0
contador_lock = Lock()

@app.get("/")
def inicio() -> dict[str, object]:
    return {
        "servidor": nombre,
        "mensaje" : "Servidor disponible",
        "puerto" : puerto
    }
@app.get("/procesar")
def procesar() -> dict[str, object]:
    global contador
    with contador_lock:
        contador += 1
        numero = contador
    return {
        "servidor": nombre,
        "puerto" : puerto,
        "mensaje" : "Solicitudes recibidas",
        "contador" : numero,
        "resultado" : "Solicitudes procesadas correctamente"
        
        
    }

@app.get("/health")
def health() -> dict[str, object]:
    return {
         "servidor": nombre,
         "estado" : "Activo",
         "puerto" : puerto,


    }

def main() -> None:
    global puerto, nombre
    parser = argparse.ArgumentParser(description="Servidor de la Red Dinamica")
    parser.add_argument("puerto", type=int, help="Puerto donde escuchara el servidor")
    parser.add_argument("nombre", help="Nombre del servidor")
    args = parser.parse_args()
    puerto, nombre = args.puerto, args.nombre
    uvicorn.run(
        app,
        host="127.0.0.1",
        port=puerto
    )


if __name__ == "__main__":
    main()