# coding=utf-8
import base64
import io
import urllib.request
from typing import Tuple, Optional, List, Any

import numpy as np
import soundfile as sf
import torch

_asr_model = None

LANGUAGE_CODE_MAP = {
    "en": "English",
    "zh": "Chinese",
    "yue": "Cantonese",
    "ar": "Arabic",
    "de": "German",
    "fr": "French",
    "es": "Spanish",
    "pt": "Portuguese",
    "id": "Indonesian",
    "it": "Italian",
    "ko": "Korean",
    "ru": "Russian",
    "th": "Thai",
    "vi": "Vietnamese",
    "ja": "Japanese",
    "tr": "Turkish",
    "hi": "Hindi",
    "ms": "Malay",
    "nl": "Dutch",
    "sv": "Swedish",
    "da": "Danish",
    "fi": "Finnish",
    "pl": "Polish",
    "cs": "Czech",
    "fil": "Filipino",
    "fa": "Persian",
    "el": "Greek",
    "ro": "Romanian",
    "hu": "Hungarian",
    "mk": "Macedonian",
}


def _normalize_language(language: Optional[str]) -> Optional[str]:
    if language is None:
        return None
    lang_lower = language.lower().strip()
    if lang_lower in LANGUAGE_CODE_MAP:
        return LANGUAGE_CODE_MAP[lang_lower]
    if language in LANGUAGE_CODE_MAP.values():
        return language
    return None


def _download_audio_bytes(url: str, timeout: int = 30) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read()


def _read_wav_from_bytes(audio_bytes: bytes) -> Tuple[np.ndarray, int]:
    with io.BytesIO(audio_bytes) as f:
        wav, sr = sf.read(f, dtype="float32", always_2d=False)
    return np.asarray(wav, dtype=np.float32), int(sr)


def _to_data_url_base64(audio_bytes: bytes, mime: str = "audio/wav") -> str:
    b64 = base64.b64encode(audio_bytes).decode("utf-8")
    return f"data:{mime};base64,{b64}"


def init_model(
    model_path: str = "Qwen/Qwen3-ASR-1.7B",
    forced_aligner_path: str = "Qwen/Qwen3-ForcedAligner-0.6B",
    device: str = "cuda:0",
    dtype: str = "bfloat16",
    max_inference_batch_size: int = 32,
    max_new_tokens: int = 128,
) -> bool:
    global _asr_model
    
    print(f"[init_model] Starting initialization with model_path={model_path}")
    try:
        import qwen_asr as qwen_asr_pkg
        Qwen3ASRModel = qwen_asr_pkg.Qwen3ASRModel
        print(f"[init_model] Imported Qwen3ASRModel")
        
        dtype_map = {
            "bfloat16": torch.bfloat16,
            "float16": torch.float16,
            "float32": torch.float32,
        }
        torch_dtype = dtype_map.get(dtype, torch.bfloat16)
        
        print(f"[init_model] Loading model from {model_path}...")
        _asr_model = Qwen3ASRModel.from_pretrained(
            model_path,
            dtype=torch_dtype,
            device_map=device,
            forced_aligner=forced_aligner_path,
            forced_aligner_kwargs=dict(
                dtype=torch_dtype,
                device_map=device,
            ),
            max_inference_batch_size=max_inference_batch_size,
            max_new_tokens=max_new_tokens,
        )
        print(f"[init_model] Model loaded successfully")
        return True
    except Exception as e:
        print(f"Failed to init model: {e}")
        import traceback
        traceback.print_exc()
        return False


def is_model_loaded() -> bool:
    return _asr_model is not None


def transcribe(
    audio: str,
    language: Optional[str] = None,
    context: Optional[str] = None,
    return_time_stamps: bool = False,
) -> dict:
    global _asr_model
    
    if _asr_model is None:
        return {"error": "Model not initialized. Call init_model() first."}
    
    try:
        transcribe_kwargs = {
            "audio": audio,
            "language": _normalize_language(language),
        }
        if context:
            transcribe_kwargs["context"] = context
        if return_time_stamps:
            transcribe_kwargs["return_time_stamps"] = True
        
        results = _asr_model.transcribe(**transcribe_kwargs)
        
        if results and len(results) > 0:
            r = results[0]
            result_dict = {
                "language": r.language,
                "text": r.text,
                "time_stamps": [],
            }
            if r.time_stamps is not None:
                for ts in r.time_stamps:
                    result_dict["time_stamps"].append({
                        "text": ts.text,
                        "start_time": ts.start_time,
                        "end_time": ts.end_time,
                    })
            return result_dict
        return {"error": "No results"}
    except Exception as e:
        return {"error": str(e)}


def transcribe_from_samples(
    samples: List[float],
    sample_rate: int,
    language: Optional[str] = None,
    context: Optional[str] = None,
    return_time_stamps: bool = False,
) -> dict:
    global _asr_model
    
    if _asr_model is None:
        return {"error": "Model not initialized. Call init_model() first."}
    
    try:
        audio_array = np.array(samples, dtype=np.float32)
        
        transcribe_kwargs = {
            "audio": (audio_array, sample_rate),
            "language": _normalize_language(language),
        }
        if context:
            transcribe_kwargs["context"] = context
        if return_time_stamps:
            transcribe_kwargs["return_time_stamps"] = True
        
        results = _asr_model.transcribe(**transcribe_kwargs)
        
        if results and len(results) > 0:
            r = results[0]
            result_dict = {
                "language": r.language,
                "text": r.text,
                "time_stamps": [],
            }
            if r.time_stamps is not None:
                for ts in r.time_stamps:
                    result_dict["time_stamps"].append({
                        "text": ts.text,
                        "start_time": ts.start_time,
                        "end_time": ts.end_time,
                    })
            return result_dict
        return {"error": "No results"}
    except Exception as e:
        return {"error": str(e)}


def transcribe_batch(
    audio_list: List[str],
    language_list: Optional[List[Optional[str]]] = None,
    context_list: Optional[List[str]] = None,
    return_time_stamps: bool = False,
) -> List[dict]:
    global _asr_model
    
    if _asr_model is None:
        return [{"error": "Model not initialized. Call init_model() first."}]
    
    try:
        contexts = context_list or [""] * len(audio_list)
        languages = [_normalize_language(lang) for lang in (language_list or [None] * len(audio_list))]
        
        results = _asr_model.transcribe(
            audio=audio_list,
            language=languages,
            context=contexts,
            return_time_stamps=return_time_stamps,
        )
        
        output = []
        for r in results:
            result_dict = {
                "language": r.language,
                "text": r.text,
                "time_stamps": [],
            }
            if r.time_stamps is not None:
                for ts in r.time_stamps:
                    result_dict["time_stamps"].append({
                        "text": ts.text,
                        "start_time": ts.start_time,
                        "end_time": ts.end_time,
                    })
            output.append(result_dict)
        return output
    except Exception as e:
        return [{"error": str(e)}]
