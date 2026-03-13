# llama.cpp Model Deployment & Optimization
# Adapted from T-002 for llama.cpp instead of Ollama

# Test basic llama.cpp functionality
echo "Testing llama.cpp installation..."
cd Tools\bin
.\llama-cli.exe -m "..\models\small-elite\llama-3.2-1b-instruct-q4_k_m.gguf" -p "Hello, how are you?" -n 10 --temp 0.7

# Test with optimized settings for i5-9500
echo "Testing with hardware optimization..."
.\llama-cli.exe -m "..\models\small-elite\llama-3.2-1b-instruct-q4_k_m.gguf" -p "What is 2+2?" -n 5 --temp 0.7 -t 6 -c 2048 --batch-size 512

# Test embedding model equivalent
echo "Testing embedding capabilities..."
.\llama-cli.exe -m "..\models\small-elite\qwen2.5-1.5b-instruct-q4_k_m.gguf" -p "Embed this test sentence" -n 1 --ctx-size 512

echo "Basic tests completed."
