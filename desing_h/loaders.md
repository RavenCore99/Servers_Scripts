# Librerias utiles para instalar con python para loaders en terminal:

&nbsp;

tqdm  para barras de progreso

`halo` o `rich` (para spinners y formateo avanzado).&nbsp;

# 

# Spinner de barra

&nbsp;

´´´bash

import time

import sys

&nbsp;

def spinner\_clasico():

&nbsp;&nbsp;&nbsp;&nbsp;\# Los caracteres que darán la ilusión de giro

&nbsp;&nbsp;&nbsp;&nbsp;secuencia \= \['\|', '/', '-', '\\\\'\]

&nbsp;&nbsp;&nbsp;&nbsp;

&nbsp;&nbsp;&nbsp;&nbsp;for i in range(20): \# Repetir 20 veces

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;\# Elegir el carácter actual usando el operador módulo

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;char \= secuencia\[i % len(secuencia)\]

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;\# \\r vuelve al inicio de la línea. flush=True fuerza la impresión.

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;print(f'\\rCargando datos... {char}', end='', flush=True)

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;\# Pausa para que el ojo humano vea la animación

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;time.sleep(0.1)

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;

&nbsp;&nbsp;&nbsp;&nbsp;print("\\n¡Carga completada\!")

&nbsp;

spinner\_clasico()

&nbsp;

´´´´

&nbsp;

# Spinner de cuadro estilo braile

´´´´bash

import time

&nbsp;

def spinner\_braille():

&nbsp;&nbsp;&nbsp;&nbsp;\# Secuencia de caracteres Unicode de Braille para hacer la animación suave

&nbsp;&nbsp;&nbsp;&nbsp;frames \= \['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'\]

&nbsp;&nbsp;&nbsp;&nbsp;

&nbsp;&nbsp;&nbsp;&nbsp;for i in range(30):

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;frame \= frames\[i % len(frames)\]

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;print(f'\\rProcesando {frame}', end='', flush=True)

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;time.sleep(0.08)

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;

&nbsp;&nbsp;&nbsp;&nbsp;print("\\n¡Proceso finalizado\!")

&nbsp;

spinner\_braille()

&nbsp;

´´´´