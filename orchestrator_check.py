import sys

print("python:", sys.version)
try:
    import torch
    print("torch:", torch.__version__, "cuda:", torch.version.cuda, "cuda_available:", torch.cuda.is_available())
except Exception as e:
    print("torch import error:", e)

try:
    import requests
    print("requests:", requests.__version__)
except Exception as e:
    print("requests import error:", e)
