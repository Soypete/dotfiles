# Exo Cluster - Models Guide

This guide explains how to download and use models from Hugging Face with your exo cluster.

## How Exo Handles Models

- **Automatic Download**: Models are automatically downloaded from Hugging Face on first use
- **Cache Location**: `~/.cache/exo/downloads` (or `$EXO_HOME/downloads` if set)
- **MLX Requirement**: For Apple Silicon (your Sparks), models must be in MLX format from `mlx-community`

## Model Format for Apple Silicon

Your Spark machines use the **MLX inference engine**, which ONLY supports models from the [mlx-community](https://huggingface.co/mlx-community) organization on Hugging Face.

**Key Points:**
- ✅ Models from `mlx-community/model-name` will work
- ❌ Regular Hugging Face models (without MLX conversion) will NOT work
- Models are typically available in different quantization levels (4bit, 8bit, etc.)

## Recommended Models for Your Setup

### For 2x Spark Machines (Coupled)

**Code Generation:**
- `mlx-community/DeepSeek-Coder-V2-Lite-Instruct-8bit`
- `mlx-community/Qwen2.5-Coder-7B-Instruct-4bit`
- `mlx-community/CodeLlama-13b-Instruct-hf-4bit`

**Chat/General:**
- `mlx-community/Llama-3.2-3B-Instruct-4bit` (smaller, faster)
- `mlx-community/Llama-3.1-8B-Instruct-4bit`
- `mlx-community/Qwen2.5-7B-Instruct-4bit`
- `mlx-community/Mistral-7B-Instruct-v0.3-4bit`

**Advanced (if you have enough memory):**
- `mlx-community/Llama-3.3-70B-Instruct-4bit` (requires significant RAM)
- `mlx-community/DeepSeek-V3-16bit` (very large, may need more nodes)

## How to Use Models

### 1. Via Claude Code (Recommended)

```bash
# The model is automatically downloaded on first use
exo-claude mlx-community/Llama-3.1-8B-Instruct-4bit
```

### 2. Pre-download Models

If you want to download models before using them:

```bash
# SSH to Spark 1
ssh soypete@100.87.122.109

# Use Hugging Face CLI to download
pip install huggingface_hub

# Download a model
huggingface-cli download mlx-community/Llama-3.1-8B-Instruct-4bit \
  --local-dir ~/.cache/exo/downloads/mlx-community/Llama-3.1-8B-Instruct-4bit
```

### 3. Via API (for testing)

```bash
# Create a model instance
curl -X POST http://100.87.122.109:52415/instance \
  -H "Content-Type: application/json" \
  -d '{"model_id": "mlx-community/Llama-3.1-8B-Instruct-4bit"}'

# Use the model
curl http://100.87.122.109:52415/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "mlx-community/Llama-3.1-8B-Instruct-4bit",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

## Finding More Models

Browse all MLX models: https://huggingface.co/mlx-community

**Filter by task:**
- Code: Search "coder" or "code"
- Chat: Search "instruct" or "chat"
- Small/Fast: Look for 3B, 7B with 4bit quantization
- Quality: Look for 13B, 70B models

## Quantization Levels

**4bit** (recommended for most use cases):
- Smallest size
- Faster inference
- Slight quality loss
- Best for limited memory

**8bit**:
- Medium size
- Good balance
- Better quality than 4bit

**16bit/full precision**:
- Largest size
- Slowest inference
- Best quality
- Requires significant memory

## Troubleshooting

### Model Not Found
If exo can't find a model, ensure:
1. It's from `mlx-community` (not just any HuggingFace model)
2. You have internet connectivity for first download
3. The model name is exact (case-sensitive)

### Out of Memory
If you run out of memory:
1. Use a smaller model (3B instead of 7B)
2. Use higher quantization (4bit instead of 8bit)
3. Add your Mac Studio to the cluster for more compute

### Slow Downloads
If downloads are slow:
1. Set `HF_ENDPOINT` if you need to use a proxy
2. Pre-download models using `huggingface-cli`
3. Download on one Spark, then copy to the other

## Environment Variables

```bash
# Change model cache location
export EXO_HOME="/path/to/custom/location"

# Use Hugging Face proxy (for censored regions)
export HF_ENDPOINT="https://your-proxy-endpoint.com"
```
