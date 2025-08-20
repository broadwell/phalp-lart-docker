#!/bin/bash

# Batch PHALP/LART Video Processor
# Processes videos one at a time, with GPU selection and error handling

# Configuration
VIDEO_SOURCE_DIR="" # Can be any folder on the host machine
MIME_DIR="" # The folder in which the Dockerfile is stored
INOUT_DIR="$MIME_DIR/inout"
LOG_DIR="$MIME_DIR/logs"
STATUS_DIR="$MIME_DIR/status"
GPU_MODE="single"  # Options: "single", "both", "parallel"
GPU_ID=0  # For single GPU mode: which GPU to use (0, 1, 2, etc.)
PARALLEL_JOBS=2  # For parallel mode: how many videos to process simultaneously
MIN_GPU_MEM=10000  # Minimum free GPU memory in MB required to start processing
VIDEO_EXTENSIONS=("mp4" "mkv" "webm") # Allowed video extensions for PHALP and LART
EMAIL_RECIPIENT="someone@domain.com"
EMAIL_INTERVAL=43200  # 12 hours in seconds

# Create directories
mkdir -p "$LOG_DIR"
mkdir -p "$INOUT_DIR"
mkdir -p "$STATUS_DIR"

# Initialize status tracking
STATS_FILE="$STATUS_DIR/processing_stats.txt"
LAST_EMAIL_FILE="$STATUS_DIR/last_email_time.txt"
START_TIME_FILE="$STATUS_DIR/start_time.txt"

# Initialize tracking files if they don't exist
[ ! -f "$STATS_FILE" ] && echo "0" > "$STATS_FILE"  # Total processed count
[ ! -f "$START_TIME_FILE" ] && date +%s > "$START_TIME_FILE"
[ ! -f "$LAST_EMAIL_FILE" ] && echo "0" > "$LAST_EMAIL_FILE"

# Initialize timing CSV header if it doesn't exist
if [ ! -f "$LOG_DIR/timing_data.csv" ]; then
    echo "timestamp,filename,gpu_id,phalp_duration_sec,lart_duration_sec,total_duration_sec" > "$LOG_DIR/timing_data.csv"
fi

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_DIR/batch_process.log"
}

# Update statistics
update_stats() {
    local action="$1"  # "success" or "failure"
    local current_count=$(cat "$STATS_FILE")
    
    if [ "$action" = "success" ]; then
        echo $((current_count + 1)) > "$STATS_FILE"
        echo "$(date +%s):success:$(basename "$2")" >> "$STATUS_DIR/processing_history.txt"
    elif [ "$action" = "failure" ]; then
        echo "$(date +%s):failure:$(basename "$2")" >> "$STATUS_DIR/processing_history.txt"
    fi
}

# Calculate processing statistics
get_processing_stats() {
    local total_processed=$(cat "$STATS_FILE")
    local current_time=$(date +%s)
    local last_email_time=$(cat "$LAST_EMAIL_FILE")
    local start_time=$(cat "$START_TIME_FILE")
    
    # Count videos processed in last 12 hours
    local twelve_hours_ago=$((current_time - EMAIL_INTERVAL))
    local recent_processed=0
    if [ -f "$STATUS_DIR/processing_history.txt" ]; then
        recent_processed=$(awk -F: -v cutoff="$twelve_hours_ago" '$1 > cutoff && $2 == "success" {count++} END {print count+0}' "$STATUS_DIR/processing_history.txt")
    fi
    
    # Count total videos remaining
    local total_videos=$(find "$VIDEO_SOURCE_DIR" -name "*.mp4" -o -name "*.mkv" -o -name "*.webm" | wc -l)
    local remaining_videos=$((total_videos - total_processed))
    
    # Calculate average processing time and estimate
    local elapsed_time=$((current_time - start_time))
    local estimated_completion="Unknown"
    if [ $total_processed -gt 0 ] && [ $remaining_videos -gt 0 ]; then
        local avg_time_per_video=$((elapsed_time / total_processed))
        local estimated_seconds=$((remaining_videos * avg_time_per_video))
        estimated_completion=$(format_duration $estimated_seconds)
    fi
    
    echo "$total_processed:$recent_processed:$remaining_videos:$estimated_completion"
}

# Format duration in human readable format
format_duration() {
    local seconds=$1
    local days=$((seconds / 86400))
    local hours=$(((seconds % 86400) / 3600))
    local minutes=$(((seconds % 3600) / 60))
    
    if [ $days -gt 0 ]; then
        echo "${days}d ${hours}h ${minutes}m"
    elif [ $hours -gt 0 ]; then
        echo "${hours}h ${minutes}m"
    else
        echo "${minutes}m"
    fi
}

# Send status email
send_status_email() {
    local stats=$(get_processing_stats)
    IFS=':' read -r total_processed recent_processed remaining_videos estimated_completion <<< "$stats"
    
    local current_time=$(date '+%Y-%m-%d %H:%M:%S')
    local hostname=$(hostname)
    
    # Create email content
    local email_subject="PHALP/LART Processing Status Update - $hostname"
    local email_body="PHALP/LART Video Processing Status Report
Generated: $current_time
Server: $hostname

📊 PROCESSING STATISTICS:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✅ Total videos processed: $total_processed
🕐 Processed in last 12 hours: $recent_processed
📹 Videos remaining: $remaining_videos
⏱️  Estimated completion time: $estimated_completion

🎮 GPU Configuration: $GPU_MODE
📁 Processing directory: $VIDEO_SOURCE_DIR
📝 Log directory: $LOG_DIR

💾 Current disk usage:
$(du -sh "$INOUT_DIR/results"* 2>/dev/null || echo "No results yet")

🔄 Processing rate: $(echo "scale=2; $recent_processed / 12" | bc 2>/dev/null || echo "N/A") videos/hour (last 12h)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

This is an automated status update from the PHALP/LART batch processor.
For detailed logs, check: $LOG_DIR/batch_process.log

Recent processing activity:
$(tail -10 "$STATUS_DIR/processing_history.txt" 2>/dev/null | while IFS=':' read -r timestamp status filename; do
    formatted_time=$(date -d "@$timestamp" '+%m/%d %H:%M' 2>/dev/null || echo "N/A")
    if [ "$status" = "success" ]; then
        echo "✅ $formatted_time - $filename"
    else
        echo "❌ $formatted_time - $filename"
    fi
done | tail -5)
"

    # Send email using mail command (most common on Linux systems)
    if command -v mail >/dev/null 2>&1; then
        echo "$email_body" | mail -s "$email_subject" "$EMAIL_RECIPIENT"
        log "📧 Status email sent to $EMAIL_RECIPIENT"
    elif command -v sendmail >/dev/null 2>&1; then
        {
            echo "To: $EMAIL_RECIPIENT"
            echo "Subject: $email_subject"
            echo ""
            echo "$email_body"
        } | sendmail "$EMAIL_RECIPIENT"
        log "📧 Status email sent to $EMAIL_RECIPIENT (via sendmail)"
    else
        log "⚠️  Cannot send email - no mail command available"
        # Save email to file as backup
        echo "$email_body" > "$LOG_DIR/status_email_$(date +%Y%m%d_%H%M%S).txt"
        log "📄 Status report saved to log file instead"
    fi
    
    # Update last email time
    date +%s > "$LAST_EMAIL_FILE"
}

# Check for required dependencies
check_dependencies() {
    local missing=""
    local warnings=""
    
    # Check essential commands
    for cmd in nvidia-smi docker bc; do
        if ! command -v "$cmd" &> /dev/null; then
            missing="$missing $cmd"
        fi
    done
    
    # Special check for mailer (not essential, but warn user)
    if ! command -v "mail" &> /dev/null && ! command -v "sendmail" &> /dev/null; then
        warnings="$warnings\n⚠️  Warning: Neither 'mail' nor 'sendmail' found. Email notifications will be saved to log files instead."
    fi
    
    # Check if find command supports required options
    if ! find /tmp -maxdepth 0 -print0 &> /dev/null; then
        missing="$missing find(with-print0-support)"
    fi
    
    # Print warnings first
    if [ -n "$warnings" ]; then
        echo -e "$warnings"
    fi
    
    # Exit if essential commands are missing
    if [ -n "$missing" ]; then
        echo "❌ Error: Missing required commands:$missing"
        echo ""
        echo "Please install missing dependencies:"
        echo "  - nvidia-smi: Usually comes with NVIDIA drivers"
        echo "  - docker: Container runtime"
        echo "  - bc: Basic calculator for math operations"
        echo "  - find: File search utility (should be standard)"
        echo ""
        echo "Optional (for email notifications):"
        echo "  - mail: sudo apt-get install mailutils"
        echo "  - sendmail: sudo apt-get install sendmail"
        exit 1
    fi
    
    # Test Docker access
    if ! docker ps &> /dev/null; then
        echo "❌ Error: Cannot access Docker daemon."
        echo "Make sure Docker is running and you have permission to use it."
        echo "Try: sudo usermod -aG docker \$USER && newgrp docker"
        exit 1
    fi
    
    # Test NVIDIA GPU access
    if ! nvidia-smi &> /dev/null; then
        echo "❌ Error: Cannot access NVIDIA GPUs."
        echo "Make sure NVIDIA drivers are installed and GPUs are available."
        exit 1
    fi
    
    return 0
}
check_email_schedule() {
    local current_time=$(date +%s)
    local last_email_time=$(cat "$LAST_EMAIL_FILE")
    local time_since_last=$((current_time - last_email_time))
    
    if [ $time_since_last -ge $EMAIL_INTERVAL ]; then
        send_status_email
    fi
}

# Get available GPUs
get_available_gpus() {
    nvidia-smi --query-gpu=index,memory.free --format=csv,noheader,nounits | \
    awk -v min_mem="$MIN_GPU_MEM" '$2 > min_mem {print $1}' | tr '\n' ' '
}

# Check specific GPU availability
check_gpu() {
    local gpu_id=$1
    local gpu_memory=$(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits -i $gpu_id)
    if [ "$gpu_memory" -lt $MIN_GPU_MEM ]; then  # Use configurable minimum
        return 1
    fi
    return 0
}

# Get next available GPU for processing
get_next_gpu() {
    if [ "$GPU_MODE" = "single" ]; then
        if check_gpu $GPU_ID; then
            echo $GPU_ID
        else
            echo ""
        fi
    elif [ "$GPU_MODE" = "both" ]; then
        # Return first available GPU
        local available_gpus=($(get_available_gpus))
        if [ ${#available_gpus[@]} -gt 0 ]; then
            echo ${available_gpus[0]}
        else
            echo ""
        fi
    elif [ "$GPU_MODE" = "parallel" ]; then
        # Return available GPUs up to PARALLEL_JOBS limit
        local available_gpus=($(get_available_gpus))
        local running_jobs=$(jobs -r | wc -l)
        if [ $running_jobs -lt $PARALLEL_JOBS ] && [ ${#available_gpus[@]} -gt 0 ]; then
            echo ${available_gpus[0]}
        else
            echo ""
        fi
    fi
}

# Wait for GPU to be available
wait_for_gpu() {
    local max_wait=300  # 5 minutes max wait
    local wait_time=0
    
    while true; do
        local available_gpu=$(get_next_gpu)
        if [ -n "$available_gpu" ]; then
            echo $available_gpu
            return 0
        fi
        
        if [ $wait_time -ge $max_wait ]; then
            log "⏰ Timeout waiting for GPU availability"
            return 1
        fi
        
        log "💤 No GPU available, waiting 60 seconds..."
        sleep 60
        wait_time=$((wait_time + 60))
    done
}

# Process a single video
process_video() {
    local video_file="$1"
    local gpu_id="$2"
    local filename=$(basename "$video_file")
    local base_name="${filename%.*}"
    
    # Start timing
    local start_time=$(date +%s)
    
    log "🎬 Starting processing: $filename on GPU $gpu_id"
    
    # Copy video to inout directory
    if ! cp "$video_file" "$INOUT_DIR/"; then
        log "❌ Failed to copy $filename to inout directory"
        return 1
    fi
    
    # Run PHALP
    log "🧠 Running PHALP on $filename using GPU $gpu_id..."
    local phalp_log="$LOG_DIR/phalp_${base_name}_gpu${gpu_id}.log"
    local phalp_start=$(date +%s)
    
    cd "$MIME_DIR"
    if docker run --gpus "device=$gpu_id" \
        -v "$INOUT_DIR:/app/inout" \
        ubuntu-phalp phalp "$filename" \
        > "$phalp_log" 2>&1; then
        
        local phalp_end=$(date +%s)
        local phalp_duration=$((phalp_end - phalp_start))
        log "✅ PHALP completed for $filename on GPU $gpu_id ($(format_duration $phalp_duration))"
        
        # Check if PHALP output exists
        if [ -f "$INOUT_DIR/results/${filename}.phalp.pkl" ]; then
            log "✅ PHALP output verified: ${filename}.phalp.pkl"
            
            # Run LART
            log "🔤 Running LART on $filename using GPU $gpu_id..."
            local lart_log="$LOG_DIR/lart_${base_name}_gpu${gpu_id}.log"
            local lart_start=$(date +%s)
            
            if docker run --gpus "device=$gpu_id" \
                -v "$INOUT_DIR:/app/inout" \
                ubuntu-phalp lart "${filename}.phalp.pkl" \
                > "$lart_log" 2>&1; then
                
                local lart_end=$(date +%s)
                local lart_duration=$((lart_end - lart_start))
                local total_duration=$((lart_end - start_time))
                
                log "✅ LART completed for $filename on GPU $gpu_id ($(format_duration $lart_duration))"
                log "⏱️  Total time for $filename: $(format_duration $total_duration) [PHALP: $(format_duration $phalp_duration), LART: $(format_duration $lart_duration)]"
                
                # Log timing data to CSV for analysis
                echo "$(date '+%Y-%m-%d %H:%M:%S'),$filename,$gpu_id,$phalp_duration,$lart_duration,$total_duration" >> "$LOG_DIR/timing_data.csv"
                
                # Update success statistics with timing
                update_stats "success" "$filename"
                
                # Clean up input video from inout directory
                rm "$INOUT_DIR/$filename"
                log "🧹 Cleaned up input file: $filename"
                
                # Check if it's time to send status email
                check_email_schedule
                
                return 0
            else
                local lart_end=$(date +%s)
                local lart_duration=$((lart_end - lart_start))
                local total_duration=$((lart_end - start_time))
                log "❌ LART failed for $filename on GPU $gpu_id ($(format_duration $lart_duration))"
                log "⏱️  Time before failure: $(format_duration $total_duration)"
                update_stats "failure" "$filename"
                return 1
            fi
        else
            local end_time=$(date +%s)
            local total_duration=$((end_time - start_time))
            log "❌ PHALP output not found for $filename"
            log "⏱️  Time before failure: $(format_duration $total_duration)"
            update_stats "failure" "$filename"
            return 1
        fi
    else
        local phalp_end=$(date +%s)
        local phalp_duration=$((phalp_end - phalp_start))
        log "❌ PHALP failed for $filename on GPU $gpu_id ($(format_duration $phalp_duration))"
        update_stats "failure" "$filename"
        return 1
    fi
}

# Process video in background (for parallel mode)
process_video_background() {
    local video_file="$1"
    local gpu_id="$2"
    
    # Process in background and save exit status
    (
        if process_video "$video_file" "$gpu_id"; then
            echo "SUCCESS:$(basename "$video_file")" >> "$LOG_DIR/parallel_results.tmp"
        else
            echo "FAILED:$(basename "$video_file")" >> "$LOG_DIR/parallel_results.tmp"
        fi
    ) &
}

# Resume from where we left off
get_processed_videos() {
    # Check what's already been processed by looking for result files
    find "$INOUT_DIR/results" -name "*.phalp.pkl" 2>/dev/null | \
        sed 's|.*/||' | sed 's|\.phalp\.pkl$||' > /tmp/processed_videos.txt
}

# Main processing loop
main() {
    log "🚀 Starting batch PHALP/LART processing"
    log "📁 Source directory: $VIDEO_SOURCE_DIR"
    log "🎮 GPU Mode: $GPU_MODE"
    if [ "$GPU_MODE" = "single" ]; then
        log "🎮 Using GPU: $GPU_ID"
    elif [ "$GPU_MODE" = "parallel" ]; then
        log "🎮 Max parallel jobs: $PARALLEL_JOBS"
    fi
    log "📝 Logs in: $LOG_DIR"
    
    # Get list of already processed videos
    get_processed_videos
    
    # Find all video files
    local video_files=()
    for ext in "${VIDEO_EXTENSIONS[@]}"; do
        while IFS= read -r -d '' file; do
            video_files+=("$file")
        done < <(find "$VIDEO_SOURCE_DIR" -name "*.${ext}" -print0)
    done
    
    if [ ${#video_files[@]} -eq 0 ]; then
        log "❌ No video files found in $VIDEO_SOURCE_DIR"
        exit 1
    fi
    
    log "📹 Found ${#video_files[@]} video files to process"
    
    # Initialize counters
    local success_count=0
    local failure_count=0
    rm -f "$LOG_DIR/parallel_results.tmp"
    
    # Process videos based on mode
    if [ "$GPU_MODE" = "parallel" ]; then
        # Parallel processing mode
        for video_file in "${video_files[@]}"; do
            local filename=$(basename "$video_file")
            local base_name="${filename%.*}"
            
            # Skip if already processed
            if grep -q "^${base_name}$" /tmp/processed_videos.txt 2>/dev/null; then
                log "⏭️  Skipping already processed: $filename"
                continue
            fi
            
            # Wait for available GPU and job slot
            local gpu_id
            while true; do
                gpu_id=$(wait_for_gpu)
                if [ -n "$gpu_id" ]; then
                    break
                fi
                sleep 30
            done
            
            log "🎬 Starting $filename on GPU $gpu_id (background)"
            process_video_background "$video_file" "$gpu_id"
            
            # Brief pause between job starts
            sleep 10
        done
        
        # Wait for all background jobs to complete
        log "⏳ Waiting for all parallel jobs to complete..."
        wait
        
        # Count results from parallel processing
        if [ -f "$LOG_DIR/parallel_results.tmp" ]; then
            success_count=$(grep "^SUCCESS:" "$LOG_DIR/parallel_results.tmp" | wc -l)
            failure_count=$(grep "^FAILED:" "$LOG_DIR/parallel_results.tmp" | wc -l)
        fi
        
    else
        # Sequential processing (single or both mode)
        for video_file in "${video_files[@]}"; do
            local filename=$(basename "$video_file")
            local base_name="${filename%.*}"
            
            # Skip if already processed
            if grep -q "^${base_name}$" /tmp/processed_videos.txt 2>/dev/null; then
                log "⏭️  Skipping already processed: $filename"
                continue
            fi
            
            # Wait for available GPU
            local gpu_id=$(wait_for_gpu)
            if [ -z "$gpu_id" ]; then
                log "❌ No GPU became available for $filename"
                ((failure_count++))
                continue
            fi
            
            if process_video "$video_file" "$gpu_id"; then
                ((success_count++))
                log "🎉 Successfully processed: $filename (Success: $success_count, Failed: $failure_count)"
            else
                ((failure_count++))
                log "💥 Failed to process: $filename (Success: $success_count, Failed: $failure_count)"
            fi
            
            # Brief pause between videos
            sleep 5
        done
    fi
    
    log "🏁 Batch processing complete!"
    log "📊 Final stats: $success_count successful, $failure_count failed"
    
    # Send final status email
    send_status_email
    
    # Show disk usage
    log "💾 Disk usage in results directory:"
    du -sh "$INOUT_DIR/results"* 2>/dev/null | tee -a "$LOG_DIR/batch_process.log"
    
    # Cleanup
    rm -f "$LOG_DIR/parallel_results.tmp"
    
    # Show timing summary
    if [ -f "$LOG_DIR/timing_data.csv" ] && [ $(wc -l < "$LOG_DIR/timing_data.csv") -gt 1 ]; then
        log "⏱️  TIMING SUMMARY:"
        log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        # Calculate averages using awk
        local timing_stats=$(awk -F',' '
        NR > 1 {  # Skip header
            total_time += $6
            phalp_time += $4
            lart_time += $5
            count++
        }
        END {
            if (count > 0) {
                avg_total = total_time / count
                avg_phalp = phalp_time / count
                avg_lart = lart_time / count
                printf "%.0f,%.0f,%.0f,%d", avg_total, avg_phalp, avg_lart, count
            }
        }' "$LOG_DIR/timing_data.csv")
        
        if [ -n "$timing_stats" ]; then
            IFS=',' read -r avg_total avg_phalp avg_lart processed_count <<< "$timing_stats"
            log "📊 Average times (based on $processed_count videos):"
            log "   • Total per video: $(format_duration $avg_total)"
            log "   • PHALP phase: $(format_duration $avg_phalp)"
            log "   • LART phase: $(format_duration $avg_lart)"
            
            # Calculate estimates for remaining videos if any
            if [ $remaining_videos -gt 0 ]; then
                local estimated_total_seconds=$((remaining_videos * avg_total))
                log "   • Estimated time for $remaining_videos remaining videos: $(format_duration $estimated_total_seconds)"
            fi
        fi
        
        log "📈 Detailed timing data saved to: $LOG_DIR/timing_data.csv"
    fi
}

# Handle interruption gracefully
trap 'log "⏹️  Processing interrupted by user"; exit 130' INT

# Run main function
main "$@"
