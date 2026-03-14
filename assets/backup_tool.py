import os
import shutil
import hashlib
import json
import argparse
from pathlib import Path
from datetime import datetime

CONFIG_FILE = "D:/Games/config.json"

def get_dir_hash(directory):
    """Calculates a hash based on file contents."""
    hasher = hashlib.md5()
    for path in sorted(Path(directory).rglob('*')):
        if path.is_file():
            try:
                with open(path, 'rb') as f:
                    while chunk := f.read(8192):
                        hasher.update(chunk)
            except OSError:
                continue 
    return hasher.hexdigest()

def get_size(start_path='.'):
    """Calculates total size of a directory in human-readable format."""
    total_size = 0
    for dirpath, dirnames, filenames in os.walk(start_path):
        for f in filenames:
            fp = os.path.join(dirpath, f)
            # skip if it is symbolic link
            if not os.path.islink(fp):
                total_size += os.path.getsize(fp)
    
    # Convert to readable format
    for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
        if total_size < 1024.0:
            return f"{total_size:.2f} {unit}"
        total_size /= 1024.0
    return f"{total_size:.2f} PB"

def rotate_zips(directory, game_name):
    """Rotates zip files, keeping only the 3 most recent."""
    z3 = directory / f"{game_name}_3.zip"
    z2 = directory / f"{game_name}_2.zip"
    z1 = directory / f"{game_name}_1.zip"

    if z3.exists(): z3.unlink()
    if z2.exists(): z2.rename(z3)
    if z1.exists(): z1.rename(z2)
    
    return z1

def run_backup(force_target=None, zip_target=None):
    if not os.path.exists(CONFIG_FILE):
        print(f"Error: {CONFIG_FILE} not found.")
        return

    with open(CONFIG_FILE, 'r') as f:
        config = json.load(f)

    backup_base = Path(config.get("backup_destination", "D:/Games"))
    backup_base.mkdir(parents=True, exist_ok=True)
    
    config_changed = False
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    for game in config.get("games", []):
        name = game['name']
        source = Path(game['path'])
        
        # Flags check
        is_forced = (force_target == "all" or force_target == name)
        should_zip = (zip_target == "all" or zip_target == name)
        
        if not source.exists():
            print(f"Skipping {name}: Source path not found.")
            continue

        needs_update = False
        current_hash = ""

        # Logic: If forced or zipped via CLI, bypass hash comparison
        if is_forced or should_zip:
            needs_update = True
            current_hash = get_dir_hash(source) 
        else:
            current_hash = get_dir_hash(source)
            if current_hash != game.get("last_hash", ""):
                needs_update = True

        if needs_update:
            print(f"Processing {name}...")
            target_folder = backup_base / name
            target_folder.mkdir(parents=True, exist_ok=True)
            
            # Calculate size for config
            game_size = get_size(source)
            
            info_text = (
                f"Game Name: {name}\n"
                f"Original Path: {source.absolute()}\n"
                f"Backup Date: {timestamp}\n"
                f"File Hash: {current_hash}\n"
                f"Size: {game_size}\n"
            )

            if should_zip:
                temp_dir = backup_base / f"temp_{name}"
                if temp_dir.exists(): shutil.rmtree(temp_dir)
                shutil.copytree(source, temp_dir)
                (temp_dir / "path.txt").write_text(info_text)
                
                new_zip_path = rotate_zips(target_folder, name)
                shutil.make_archive(str(new_zip_path.with_suffix('')), 'zip', temp_dir)
                
                shutil.rmtree(temp_dir)
                game["last_zipped"] = timestamp
                print(f"Zipped backup (Size: {game_size}) created for {name}.")
            else:
                # Regular folder sync
                for item in target_folder.iterdir():
                    if item.is_dir(): shutil.rmtree(item)
                    elif item.is_file() and item.suffix != ".zip": item.unlink()
                
                for item in source.iterdir():
                    if item.is_dir(): shutil.copytree(item, target_folder / item.name)
                    else: shutil.copy(item, target_folder / item.name)
                
                (target_folder / "path.txt").write_text(info_text)
                print(f"Folder backup (Size: {game_size}) updated for {name}.")

            # Update config metadata
            game["last_hash"] = current_hash
            game["last_backup"] = timestamp
            game["size"] = game_size
            config_changed = True
        else:
            print(f"No changes for {name}. Skipping.")

    if config_changed:
        with open(CONFIG_FILE, 'w') as f:
            json.dump(config, f, indent=4)
        print("\nProcess complete. Config updated.")

def main():
    parser = argparse.ArgumentParser(description="Game Backup Tool")
    parser.add_argument("--force", metavar="NAME", help="Force backup for 'all' or a specific game name.")
    parser.add_argument("--zip", metavar="NAME", help="Zip backup for 'all' or a specific game name.")

    args = parser.parse_args()
    run_backup(force_target=args.force, zip_target=args.zip)

if __name__ == "__main__":
    main()