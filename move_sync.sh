#!/bin/bash

# ==========================================
# 🚀 配置区域
# ==========================================
SOURCE_DIR="/source"
DEST_DIR="/dest"

# 🎯 目标语言列表 (空格分隔)
# 添加了 spa (西班牙语), es (西班牙语简写), jpn (日语), kor (韩语) 以防万一
TARGET_LANGS="chi zho eng spa es jpn kor" 

INTERVAL=60
HISTORY_FILE="$SOURCE_DIR/.processed_history.log"

# 环境检查
if ! command -v ffmpeg &> /dev/null; then
    echo "❌ 严重错误: 未找到 ffmpeg"
    exit 1
fi

if [ ! -f "$HISTORY_FILE" ]; then
    touch "$HISTORY_FILE"
fi

echo "🚀 最终修正版: 修复ID丢失(竖线分隔) + 添加SPA支持 + 智能硬链"

while true; do
    find "$SOURCE_DIR" -type f -name "*.mkv" | while read -r source_file; do
        
        filename=$(basename -- "$source_file")
        source_dirname=$(dirname -- "$source_file")
        filename_no_ext="${filename%.*}"

        relative_path="${source_dirname#$SOURCE_DIR}/${filename}"
        target_dirname="$DEST_DIR${source_dirname#$SOURCE_DIR}"
        target_video_path="${target_dirname}/${filename}"

        # === Step 0: 防重复检测 ===
        if grep -Fxq "$relative_path" "$HISTORY_FILE"; then
            continue
        fi
        
        if [ -f "$target_video_path" ]; then
            echo "$relative_path" >> "$HISTORY_FILE"
            continue
        fi

        # === Step 1: 写入稳定性检测 ===
        size1=$(stat -c%s "$source_file")
        sleep 1
        size2=$(stat -c%s "$source_file")
        if [ "$size1" != "$size2" ]; then
            continue
        fi

        # === Step 2: 准备目录 ===
        if [ ! -d "$target_dirname" ]; then
            mkdir -p "$target_dirname"
            chmod 777 "$target_dirname"
        fi

        echo "---------------------------------------------------"
        echo "🎬 处理任务: $filename"

        # === Step 3: 同步源目录自带的外挂字幕 (硬链接) ===
        find "$source_dirname" -maxdepth 1 -type f \( -name "${filename_no_ext}*.ass" -o -name "${filename_no_ext}*.srt" \) | while read -r src_sub_file; do
            sub_filename=$(basename -- "$src_sub_file")
            dest_sub_file="${target_dirname}/${sub_filename}"
            if [ ! -f "$dest_sub_file" ]; then
                echo "   🔗 [硬链] 同步外挂字幕: $sub_filename"
                ln "$src_sub_file" "$dest_sub_file" 2>/dev/null || cp "$src_sub_file" "$dest_sub_file"
                chmod 777 "$dest_sub_file"
            fi
        done

        # === Step 4: 检测视频是否含有字幕流 ===
        sub_count=$(ffprobe -v error -select_streams s -show_entries stream=index -of csv=p=0 "$source_file" | wc -l)

        if [ "$sub_count" -eq 0 ]; then
            # --- 分支 A: 无内封字幕 -> 硬链接 ---
            echo "   ⚡ [极速] 无内封字幕 -> 建立硬链接..."
            ln "$source_file" "$target_video_path" 2>/dev/null
            if [ $? -ne 0 ]; then
                cp "$source_file" "$target_video_path"
            fi
            
            if [ -f "$target_video_path" ]; then
                echo "   ✅ [完成] 视频已同步。"
                chmod 777 "$target_video_path"
                echo "$relative_path" >> "$HISTORY_FILE"
            fi

        else
            # --- 分支 B: 有内封字幕 -> 提取并清洗 ---
            echo "   🔍 [检测] 发现 $sub_count 条内封字幕 -> 提取并清洗"

            # 🌟🌟🌟 核心修正：使用竖线 | 作为分隔符，防止标题中的逗号导致错位 🌟🌟🌟
            ffprobe -v error -select_streams s \
                -show_entries stream=index,codec_name:stream_tags=language,title \
                -of csv=p=0:s="|" "$source_file" | while IFS="|" read -r stream_index codec lang title; do
                
                # 处理空语言
                lang=${lang:-und}

                # 检查语言是否在白名单中 (grep -w 全词匹配)
                if echo "$TARGET_LANGS" | grep -qw "$lang"; then
                    
                    target_ext=""
                    case "$codec" in
                        "ass"|"ssa") target_ext="ass" ;;
                        "subrip"|"srt") target_ext="srt" ;;
                        *) continue ;;
                    esac

                    # 标题清洗
                    if [ -z "$title" ]; then 
                        clean_title="default"
                    else
                        # 替换特殊字符和空格为点
                        clean_title=$(echo "$title" | tr -d '/\\:*?"<>|' | tr ' ' '.')
                    fi
                    
                    # 🌟🌟🌟 文件名构建：确保包含 ID 和 语言 🌟🌟🌟
                    # 格式: 视频名.LoliHouse.id2.chi.ass
                    dest_sub_file="${target_dirname}/${filename_no_ext}.${clean_title}.id${stream_index}.${lang}.${target_ext}"

                    if [ ! -f "$dest_sub_file" ]; then
                        echo "   📥 [提取] #${stream_index} [${lang}] ${clean_title} -> .${target_ext}"
                        ffmpeg -n -nostdin -i "$source_file" -map 0:"$stream_index" -c copy "$dest_sub_file" > /dev/null 2>&1
                        chmod 777 "$dest_sub_file"
                    fi
                fi
            done

            echo "   🧹 [清洗] 去除内封字幕并生成..."
            clean_output=$(ffmpeg -n -nostdin -i "$source_file" \
                -map 0 -map -0:s -c copy \
                "$target_video_path" 2>&1)
            
            if [ $? -eq 0 ] && [ -s "$target_video_path" ]; then
                echo "   ✅ [完成] 视频已净化。"
                chmod 777 "$target_video_path"
                echo "$relative_path" >> "$HISTORY_FILE"
            else
                echo "   ❌ [失败] 清洗出错，清理残留。"
                rm -f "$target_video_path" 2>/dev/null
            fi
        fi

    done

    # === Step 5: 清理空文件夹 ===
    find "$DEST_DIR" -mindepth 1 -type d -empty -delete > /dev/null 2>&1

    sleep $INTERVAL
done