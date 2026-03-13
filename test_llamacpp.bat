@echo off
echo Testing llama.cpp installation...
cd Tools\bin
.\main.exe -m "..\models\small-elite\llama-3.2-1b-instruct-q4_k_m.gguf" -p "Hello" -n 5
pause
