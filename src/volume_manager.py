#---------------------------------------------------------------------
#volume_manager.py (Karubbiyyun) from the VAULT OPUS PROJECT version 1-R10
#by WEDUXOX/WEDUOFFICIAL - https://github.com/WeDu-official
#I HAD MADE THIS PROJECT FOR FREE FOR ALL
#from mankind to mankind... if I disappear don't worry it might just be my exams or anything else, but regardless
#this code will still be here so DO GOOD NO EVIL....good luck :)
#---------------------------------------------------------------------
#[]===================THE ENCODING FIX==========================[]
from encoding_fix import apply as _fix_encoding
_fix_encoding()
#[]=================START OF ACTUAL CODE========================[]
import os
import json
import base64
import secrets
import pyzipper    # <-- REPLACED: pip install pyzipper
import shutil
import sys
import subprocess
from pathlib import Path
from datetime import datetime
from typing import Tuple, Optional

# Constants
SRC_DIR = Path(__file__).resolve().parent
VOLUMES_CONFIGS_DIR = SRC_DIR / "VOLUMES_CONFIGS"
DATABASES_DIR = SRC_DIR / "DATABASES"
SHARABLES_DIR = SRC_DIR / "SHARABLES"
HARDCODED_INFO = "VAULTOPUS-item-encryption-key"

def ensure_dirs():
    """Ensure all required directories exist."""
    VOLUMES_CONFIGS_DIR.mkdir(parents=True, exist_ok=True)
    DATABASES_DIR.mkdir(parents=True, exist_ok=True)
    SHARABLES_DIR.mkdir(parents=True, exist_ok=True)

def validate_volume_name(name: str) -> str:
    """
    Validates the volume name.
    Rejects exactly '.db'.
    Strips '.db' suffix for the stem.
    Ensures only the filename stem is returned, even if a path is provided.
    """
    path_obj = Path(name.strip())
    clean_name = path_obj.name
    
    if clean_name.lower() == ".db":
        raise ValueError("Invalid volume name: '.db' is not allowed.")
    
    if clean_name.lower().endswith(".db"):
        return clean_name[:-3]
    return clean_name

def get_config_path(volume_stem: str) -> Path:
    """Returns the path to the volume's config file."""
    return VOLUMES_CONFIGS_DIR / f"{volume_stem}_config.json"

def create_volume_config(volume_name: str) -> Path:
    """
    Creates a new volume config with a random 32-byte salt.
    """
    ensure_dirs()
    stem = validate_volume_name(volume_name)
    cfg_path = get_config_path(stem)
    
    salt = secrets.token_urlsafe(24) 
    
    config = {
        "salt": salt,
        "info": HARDCODED_INFO
    }
    
    with open(cfg_path, "w", encoding="utf-8") as f:
        json.dump(config, f, indent=2)
    
    return cfg_path

def rename_volume_config(old_name: str, new_name: str) -> Optional[Path]:
    """
    Renames a volume config sidecar to match a new volume name.
    """
    old_stem = validate_volume_name(old_name)
    new_stem = validate_volume_name(new_name)
    
    old_cfg = get_config_path(old_stem)
    new_cfg = get_config_path(new_stem)
    
    if old_cfg.exists():
        old_cfg.rename(new_cfg)
        return new_cfg
    return None

def get_volume_salt_info(db_path: str) -> Tuple[bytes, bytes]:
    """
    Retrieves the salt and info for a given database path.
    """
    stem = Path(db_path).stem
    cfg_path = get_config_path(stem)
    
    if not cfg_path.exists():
        raise FileNotFoundError(f"Encryption config missing for volume '{stem}' at {cfg_path}")
    
    with open(cfg_path, "r", encoding="utf-8") as f:
        config = json.load(f)
    
    salt_str = config.get("salt")
    salt_bytes = salt_str.encode('utf-8')
    info_bytes = config.get("info", HARDCODED_INFO).encode('utf-8')
    
    return salt_bytes, info_bytes

def make_package(volume_name: str, password: Optional[str] = None) -> Path:
    """
    Packages a volume and its config into a .vov file.
    If password is provided, creates a password-protected ZIP (AES-256).
    Encrypted packages use .e.vov extension to indicate password protection.
    """
    ensure_dirs()
    stem = validate_volume_name(volume_name)
    db_path = DATABASES_DIR / f"{stem}.db"
    cfg_path = get_config_path(stem)
    
    if not db_path.exists():
        raise FileNotFoundError(f"Database file not found: {db_path}")
    if not cfg_path.exists():
        raise FileNotFoundError(f"Config file not found: {cfg_path}")
    
    vov_filename = f"{stem}.e.vov" if password else f"{stem}.vov"
    vov_path = SHARABLES_DIR / vov_filename
    
    # Collision Handling for .vov
    if vov_path.exists():
        timestamp = datetime.now().strftime("%Y%m%dT%H%M%S")
        vov_path = SHARABLES_DIR / f"{stem}_{timestamp}.vov" if not password else SHARABLES_DIR / f"{stem}_{timestamp}.e.vov"
    
    # Files to include and their internal names
    src_files = [str(db_path), str(cfg_path)]
    arc_names = [f"{stem}.db", f"{stem}_config.json"]
    
    if password:
        # AES-256 encryption with pyzipper
        with pyzipper.AESZipFile(
            str(vov_path), 'w',
            compression=pyzipper.ZIP_DEFLATED,
            encryption=pyzipper.WZ_AES
        ) as zf:
            zf.setpassword(password.encode('utf-8'))
            zf.setencryption(pyzipper.WZ_AES, nbits=256)
            for src, arc_name in zip(src_files, arc_names):
                zf.write(src, arc_name)
    else:
        # No password - standard ZIP
        with pyzipper.AESZipFile(
            str(vov_path), 'w',
            compression=pyzipper.ZIP_DEFLATED
        ) as zf:
            for src, arc_name in zip(src_files, arc_names):
                zf.write(src, arc_name)
    
    return vov_path

def open_package(vov_path_str: str, password: Optional[str] = None) -> Tuple[str, str]:
    """
    Unzips a .vov file and imports the volume and config.
    Handles collisions with timestamp suffix.
    If password is provided, decrypts the ZIP.
    Auto-detects .e.vov extension.
    Raises RuntimeError if password is wrong.
    """
    ensure_dirs()
    vov_path = Path(vov_path_str)
    
    # Auto-detect .e.vov vs .vov extension
    if not vov_path.exists():
        if vov_path_str.lower().endswith('.vov') and not vov_path_str.lower().endswith('.e.vov'):
            alt_path = vov_path.with_suffix('').with_suffix('.e.vov')
            if alt_path.exists():
                vov_path = alt_path
        elif not vov_path_str.lower().endswith('.vov'):
            for ext in ['.vov', '.e.vov']:
                alt = Path(vov_path_str + ext)
                if alt.exists():
                    vov_path = alt
                    break
    
    if not vov_path.exists():
        raise FileNotFoundError(f"Package not found: {vov_path}")
    
    # Create temp extraction dir
    import tempfile
    temp_dir = tempfile.mkdtemp(prefix="vov_extract_")
    
    try:
        # Extract with pyzipper
        with pyzipper.AESZipFile(str(vov_path), 'r') as zf:
            if password:
                zf.setpassword(password.encode('utf-8'))
            zf.extractall(temp_dir)
        
        # Find extracted files
        extracted_files = list(Path(temp_dir).iterdir())
        db_file = next((f for f in extracted_files if f.suffix == ".db"), None)
        cfg_file = next((f for f in extracted_files if f.name.endswith("_config.json")), None)
        
        if not db_file or not cfg_file:
            raise ValueError("Invalid .vov package: Missing .db or _config.json")
        
        original_stem = db_file.stem
        target_stem = original_stem
        
        db_target = DATABASES_DIR / f"{target_stem}.db"
        cfg_target = VOLUMES_CONFIGS_DIR / f"{target_stem}_config.json"
        
        # Collision Handling for imported files
        if db_target.exists() or cfg_target.exists():
            timestamp = datetime.now().strftime("%Y%m%dT%H%M%S")
            target_stem = f"{original_stem}_{timestamp}"
            db_target = DATABASES_DIR / f"{target_stem}.db"
            cfg_target = VOLUMES_CONFIGS_DIR / f"{target_stem}_config.json"
        
        # Move files to final location
        shutil.move(str(db_file), str(db_target))
        shutil.move(str(cfg_file), str(cfg_target))
        
    except pyzipper.BadZipFile:
        raise RuntimeError("Invalid or corrupted .vov package")
    except RuntimeError as e:
        if "Bad password" in str(e) or "password required" in str(e).lower():
            raise RuntimeError("Incorrect password or password required for this package")
        raise
    
    finally:
        # Clean up temp dir
        shutil.rmtree(temp_dir, ignore_errors=True)
            
    return str(db_target), str(cfg_target)

def open_explorer_for_sharables(path_str: Optional[str] = None) -> bool:
    """
    Opens the OS file explorer at the SHARABLES directory or a specific path.
    """
    target_path = path_str if path_str else str(SHARABLES_DIR)
    path = os.path.abspath(target_path)
    try:
        if sys.platform == "win32":
            os.startfile(path)
        elif sys.platform == "darwin":
            subprocess.run(["open", path], check=True)
        else:  # Linux and others
            subprocess.run(["xdg-open", path], check=True)
        return True
    except Exception as e:
        print(f"Failed to open OS explorer: {e}")
        return False