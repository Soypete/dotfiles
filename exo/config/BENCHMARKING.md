# Exo Cluster Benchmarking Guide

This guide explains how to benchmark your exo cluster to measure model performance and optimize configurations.

## Overview

The `exo-bench` tool measures:
- **Prefill speed**: How fast the model processes the initial prompt
- **Token generation speed**: How fast the model generates new tokens
- **Different placement configurations**: How the model performs when split across nodes

This helps you:
- Optimize model performance
- Validate improvements
- Choose the best configuration for your hardware

## Prerequisites

**Before benchmarking, ensure:**
1. Both Spark nodes are running exo:
   ```bash
   # Check from Mac Studio
   curl http://100.87.122.109:52415/state
   ```

2. The model you want to benchmark is available:
   ```bash
   exo-models
   ```

## Basic Usage

### From a Spark Machine

SSH to Spark 1 and run:

```bash
cd ~/code/exo

uv run bench/exo_bench.py \
  --model mlx-community/Llama-3.2-1B-Instruct-4bit \
  --pp 128,256,512 \
  --tg 128,256
```

### What This Does

- `--model`: Model to benchmark (use model IDs from `exo-models`)
- `--pp`: Prompt sizes to test (128, 256, 512 tokens)
- `--tg`: Generation lengths to test (128, 256 tokens)

## Key Parameters

### Model Selection
```bash
--model mlx-community/Llama-3.1-8B-Instruct-4bit
```
Use the full model ID from Hugging Face (mlx-community models for your Sparks).

### Prompt Sizes (`--pp`)
```bash
--pp 128,256,512,1024
```
Comma-separated prompt sizes in tokens. Tests how fast the model processes different input lengths.

**Recommended for your 2x Spark setup:**
- Small: `128,256`
- Medium: `256,512,1024`
- Large: `512,1024,2048`

### Generation Lengths (`--tg`)
```bash
--tg 128,256,512
```
How many tokens to generate. Tests sustained generation speed.

**Recommended:**
- Quick test: `128`
- Standard: `128,256`
- Thorough: `128,256,512`

### Node Limits (`--max-nodes`)
```bash
--max-nodes 2
```
Since you have 2 Sparks, set this to `2` to only test 2-node configurations.

### Sharding Strategy (`--sharding`)
```bash
--sharding pipeline      # Only test pipeline sharding
--sharding tensor        # Only test tensor sharding
--sharding both          # Test both (default)
```

**What's the difference?**
- **Pipeline sharding**: Splits model layers across nodes (layer 1-10 on Spark 1, layer 11-20 on Spark 2)
- **Tensor sharding**: Splits individual layers across nodes (each layer computed jointly)

### Repetitions (`--repeat`)
```bash
--repeat 3
```
Run each test 3 times and average the results. More repetitions = more accurate results.

### Warmup Runs (`--warmup`)
```bash
--warmup 1
```
Run the test once before timing to "warm up" the model (load into memory, compile, etc.).

### Output File (`--json-out`)
```bash
--json-out bench/my-results.json
```
Save detailed results to a JSON file for later analysis.

## Example Benchmarks

### Quick Test (2x Spark, small model)
```bash
cd ~/code/exo

uv run bench/exo_bench.py \
  --model mlx-community/Llama-3.2-1B-Instruct-4bit \
  --pp 128,256 \
  --tg 128 \
  --max-nodes 2 \
  --repeat 1
```

### Thorough Test (2x Spark, 8B model)
```bash
cd ~/code/exo

uv run bench/exo_bench.py \
  --model mlx-community/Llama-3.1-8B-Instruct-4bit \
  --pp 128,256,512 \
  --tg 128,256 \
  --max-nodes 2 \
  --repeat 3 \
  --warmup 1 \
  --json-out bench/llama-8b-results.json
```

### Compare Sharding Strategies
```bash
cd ~/code/exo

# Test pipeline sharding
uv run bench/exo_bench.py \
  --model mlx-community/Qwen2.5-Coder-7B-Instruct-4bit \
  --pp 256,512 \
  --tg 256 \
  --max-nodes 2 \
  --sharding pipeline \
  --repeat 3 \
  --json-out bench/qwen-pipeline.json

# Test tensor sharding
uv run bench/exo_bench.py \
  --model mlx-community/Qwen2.5-Coder-7B-Instruct-4bit \
  --pp 256,512 \
  --tg 256 \
  --max-nodes 2 \
  --sharding tensor \
  --repeat 3 \
  --json-out bench/qwen-tensor.json
```

### Stress Test (Large prompts and generation)
```bash
cd ~/code/exo

uv run bench/exo_bench.py \
  --model mlx-community/Llama-3.1-8B-Instruct-4bit \
  --pp 512,1024,2048 \
  --tg 256,512 \
  --max-nodes 2 \
  --repeat 2 \
  --warmup 1 \
  --json-out bench/stress-test.json
```

## Understanding Results

The benchmark will output:
- **Prefill time**: Time to process the prompt (lower is better)
- **Tokens per second**: Generation speed (higher is better)
- **Placement configuration**: How the model was distributed across nodes

**Example output:**
```
Model: mlx-community/Llama-3.1-8B-Instruct-4bit
Prompt: 256 tokens
Generate: 128 tokens
Nodes: 2 (pipeline sharding)

Prefill: 0.8s
Generation: 45 tokens/sec
```

## Tips for Your Setup

### For 2x Spark Machines:

1. **Always set `--max-nodes 2`** (you only have 2 Sparks)

2. **Start small, go big:**
   - Test 1B model first
   - Then 3B model
   - Then 7-8B models
   - Only try larger if performance is good

3. **Compare sharding strategies:**
   - Some models work better with pipeline sharding
   - Others work better with tensor sharding
   - Test both to find the best for each model

4. **Use warmup for accurate results:**
   - First run is always slower (loading, compilation)
   - Use `--warmup 1` for more accurate timing

5. **Repeat for consistency:**
   - Use `--repeat 3` to average out variance
   - Network latency can vary between runs

## Automating Benchmarks

Create a benchmark script on your Spark:

```bash
#!/bin/bash
# ~/code/benchmark-cluster.sh

cd ~/code/exo

MODELS=(
  "mlx-community/Llama-3.2-1B-Instruct-4bit"
  "mlx-community/Llama-3.2-3B-Instruct-4bit"
  "mlx-community/Llama-3.1-8B-Instruct-4bit"
)

for MODEL in "${MODELS[@]}"; do
  echo "Benchmarking $MODEL..."

  MODEL_NAME=$(basename "$MODEL")

  uv run bench/exo_bench.py \
    --model "$MODEL" \
    --pp 128,256,512 \
    --tg 128,256 \
    --max-nodes 2 \
    --repeat 3 \
    --warmup 1 \
    --json-out "bench/results-${MODEL_NAME}.json"
done

echo "All benchmarks complete!"
echo "Results saved to: ~/code/exo/bench/"
```

Make it executable and run:
```bash
chmod +x ~/code/benchmark-cluster.sh
./benchmark-cluster.sh
```

## Analyzing Results

Results are saved as JSON files in `bench/` directory.

**View results:**
```bash
cat bench/results.json | jq '.'
```

**Compare two configurations:**
```bash
# Extract tokens/sec from each result
jq '.results[].tokens_per_sec' bench/pipeline-results.json
jq '.results[].tokens_per_sec' bench/tensor-results.json
```

## Troubleshooting

### Benchmark fails to connect

Ensure exo is running on both Sparks:
```bash
curl http://localhost:52415/state
```

### Out of memory errors

Try:
1. Smaller model (1B instead of 8B)
2. Smaller prompt sizes (`--pp 128,256`)
3. Shorter generation (`--tg 128`)

### Inconsistent results

- Increase `--repeat 5` for more samples
- Add `--warmup 2` to stabilize
- Check network stability between Sparks
- Ensure no other workloads are running

## Reference

- Benchmark endpoint: `http://localhost:52415/bench/chat/completions`
- Results location: `~/code/exo/bench/`
- All parameters: `uv run bench/exo_bench.py --help`
