"""Sidecar startup warmup -- loads ML models before accepting requests."""
import sys
import time

READY_FILE = '/tmp/models_ready'

def warmup():
    start = time.time()
    print("[warmup] Loading ML models...", flush=True)

    try:
        from transformers import pipeline
        sentinel = pipeline("text-classification", model="protectai/deberta-v3-base-prompt-injection-v2", device=-1, truncation=True, max_length=512)
        sentinel("test warmup")
        print(f"[warmup] Sentinel v2 loaded ({time.time()-start:.1f}s)", flush=True)
    except Exception as e:
        print(f"[warmup] WARNING: Sentinel v2 failed to load: {e}", file=sys.stderr, flush=True)

    try:
        from transformers import pipeline
        pg2 = pipeline("text-classification", model="meta-llama/Llama-Prompt-Guard-2-86M", device=-1, truncation=True, max_length=512)
        pg2("test warmup")
        print(f"[warmup] Prompt Guard 2 loaded ({time.time()-start:.1f}s)", flush=True)
    except Exception as e:
        print(f"[warmup] WARNING: Prompt Guard 2 failed to load: {e}", file=sys.stderr, flush=True)

    with open(READY_FILE, 'w') as f:
        f.write('ready')
    print(f"[warmup] All models ready ({time.time()-start:.1f}s)", flush=True)

if __name__ == '__main__':
    warmup()
