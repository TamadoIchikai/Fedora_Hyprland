#!/usr/bin/env bash
set -euo pipefail

INPUT_PREFIX="/mnt/sda2"
INPUT_BROWSER="AA_Zen"
OUTPUT_BROWSER="zen"
# ---- INPUT VARIABLES ----
INPUT_PROFILE="${INPUT_PREFIX}/Customization/AA_Browsers/${INPUT_BROWSER}/profile folder"
INPUT_PROFILE_FOLDER="${INPUT_PREFIX}/Customization/AA_Browsers/${INPUT_BROWSER}/Default_Linux/uz741yoe.Default (release)"
INPUT_INSTALL="${INPUT_PREFIX}/Customization/AA_Browsers/${INPUT_BROWSER}/installation folder"

# ---- OUTPUT TEST BOUNDARIES ----
# The script will ONLY search for the target folders inside these directories.
INIT_OUTPUT_PROFILE="$HOME/.config/${OUTPUT_BROWSER}"
INIT_OUTPUT_INSTALL="/opt/zen"

# =====================================================================
# 1. VERIFY INPUT FOLDERS
# =====================================================================
echo "INPUT_PROFILE: $INPUT_PROFILE"
echo "INPUT_PROFILE_FOLDER: $INPUT_PROFILE_FOLDER"
echo "INPUT_INSTALL: $INPUT_INSTALL"
echo ""

if [[ ! -d "$INPUT_PROFILE" ]]; then
    echo "⚠️  WARNING: INPUT_PROFILE directory does not exist!"
fi
if [[ ! -d "$INPUT_PROFILE_FOLDER" ]]; then
    echo "⚠️  WARNING: INPUT_PROFILE_FOLDER directory does not exist!"
fi
if [[ ! -d "$INPUT_INSTALL" ]]; then
    echo "⚠️  WARNING: INPUT_INSTALL directory does not exist!"
fi

read -p "Are these input paths correct [y/N]: " confirm_inputs
if [[ ! "$confirm_inputs" =~ ^[Yy]$ ]]; then
    echo "Aborted by user."
    exit 0
fi

# =====================================================================
# 2. FULL PROFILE FOLDER COPY (NEW)
# =====================================================================
SKIP_PROFILE_FILES=false

if [[ -d "$INPUT_PROFILE_FOLDER" ]]; then
    echo ""
    read -p "INPUT_PROFILE_FOLDER detected, do you want to apply profile folder to .config/${OUTPUT_BROWSER}? [y/N]: " confirm_full_prof
    
    if [[ "$confirm_full_prof" =~ ^[Yy]$ ]]; then
        echo "🚀 Copying entire profile folder..."
        
        # Ensure the destination parent directory exists
        mkdir -p "$INIT_OUTPUT_PROFILE"
        
        # Copy the whole folder (including the folder name itself)
        cp -a "$INPUT_PROFILE_FOLDER" "$INIT_OUTPUT_PROFILE/"
        
        echo "✅ Successfully copied $(basename "$INPUT_PROFILE_FOLDER") to $INIT_OUTPUT_PROFILE/"
        
        # Flag to skip the next section
        SKIP_PROFILE_FILES=true
    else
        echo "⏭️  Skipping full folder copy. Falling back to individual file sync."
    fi
fi

# =====================================================================
# 3. SEARCH AND COPY INDIVIDUAL PROFILE FILES
# =====================================================================
if [[ "$SKIP_PROFILE_FILES" == false ]]; then
    echo ""
    echo "🔍 Searching for actual Profile inside $INIT_OUTPUT_PROFILE..."

    OUTPUT_PROFILE=""
    if [[ -d "$INIT_OUTPUT_PROFILE" ]]; then
        # Look ONLY in the specified test directory for the profile ending in .Default (release)
        OUTPUT_PROFILE=$(find "$INIT_OUTPUT_PROFILE" -type d -name "*.Default (release)" 2>/dev/null | head -n 1)
    fi

    if [[ -n "$OUTPUT_PROFILE" ]]; then
        echo "✅ Found OUTPUT_PROFILE: $OUTPUT_PROFILE"
        read -p "Copy profile configs to this directory? [y/N]: " confirm_prof
        
        if [[ "$confirm_prof" =~ ^[Yy]$ ]]; then
            files_to_copy=(
                "places.sqlite" 
                "search.json.mozlz4" 
                "sessionCheckpoints.json" 
                "storage.sqlite" 
                "zen-sessions.jsonlz4" 
                "user.js"
                "zen-keyboard-shortcuts.json"
            )
            
            for f in "${files_to_copy[@]}"; do
                if [[ -f "$INPUT_PROFILE/$f" ]]; then
                    cp "$INPUT_PROFILE/$f" "$OUTPUT_PROFILE/"
                    echo "  -> Copied $f"
                else
                    echo "  -> ⚠️ Skipped $f (Not found in INPUT_PROFILE)"
                fi
            done
        else
            echo "⏭️  Skipping OUTPUT_PROFILE copy."
        fi
    else
        echo "❌ OUTPUT_PROFILE (*.Default (release)) not found in $INIT_OUTPUT_PROFILE. Skipping."
    fi
else
    echo ""
    echo "⏭️  Skipping individual profile files search (Full profile folder was already applied)."
fi

# =====================================================================
# 4. SEARCH AND COPY INSTALL (RESTRICTED TO INIT_OUTPUT_INSTALL)
# =====================================================================
echo ""
echo "🔍 Searching for actual Install Dir inside $INIT_OUTPUT_INSTALL..."

OUTPUT_INSTALL=""

if [[ -d "$INIT_OUTPUT_INSTALL" ]]; then
    # Search ONLY inside the specified test directory for the "zen" binary
    while IFS= read -r possible_zen; do
        candidate_dir="$(dirname "$possible_zen")"
        
        # Check the 3 strict conditions
        if [[ -f "$candidate_dir/zen" && -f "$candidate_dir/zen-bin" && -d "$candidate_dir/defaults" ]]; then
            OUTPUT_INSTALL="$candidate_dir"
            break
        fi
    done < <(find "$INIT_OUTPUT_INSTALL" -type f -name "zen" 2>/dev/null)
fi

if [[ -n "$OUTPUT_INSTALL" ]]; then
    echo "✅ Found OUTPUT_INSTALL: $OUTPUT_INSTALL"
    read -p "Copy install configs to this directory? [y/N]: " confirm_inst
    
    if [[ "$confirm_inst" =~ ^[Yy]$ ]]; then
        
        # Helper function: copies files safely, checking if directory exists, using sudo if write-protected
        copy_install_file() {
            local src_file="$1"
            local dest_dir="$2"
            
            if [[ -f "$src_file" ]]; then
                # STRICT REQUIREMENT: No mkdir. Skip if destination directory is unavailable.
                if [[ ! -d "$dest_dir" ]]; then
                    echo "  -> ❌ Skipped $(basename "$src_file"): Destination folder $dest_dir does not exist!"
                    return
                fi
                
                # Check if we have write access
                if [[ -w "$dest_dir" ]]; then
                    cp "$src_file" "$dest_dir/"
                    echo "  -> Copied $(basename "$src_file") to $dest_dir"
                else
                    echo "  -> 🔐 Elevating privileges to write to read-only directory..."
                    sudo cp "$src_file" "$dest_dir/"
                    echo "  -> Copied $(basename "$src_file") (via sudo)"
                fi
            else
                echo "  -> ⚠️ Skipped $(basename "$src_file") (Not found in INPUT_INSTALL)"
            fi
        }

        # Execute the required file copies
        copy_install_file "$INPUT_INSTALL/config.js" "$OUTPUT_INSTALL"
        copy_install_file "$INPUT_INSTALL/config-prefs.js" "$OUTPUT_INSTALL/defaults/pref"
    else
        echo "⏭️  Skipping OUTPUT_INSTALL copy."
    fi
else
    echo "❌ OUTPUT_INSTALL not found in $INIT_OUTPUT_INSTALL. Skipping."
fi

echo ""
echo "🎉 Script finished!"
