#!/bin/bash

set -e

renditions=(
# resolution  bitrate  audio-rate
  "426x240    400k     64k"
  "640x360    800k     96k"
  "842x480    1400k    128k"
  "1280x720   2800k    128k"
  "1920x1080  5000k    192k"
)
segment_target_duration=4
max_bitrate_ratio=1.07
rate_monitor_buffer_ratio=1.5
misc_params="-hide_banner -y"
source="${1}"
target="${2}"
files=(
# input  output
)

if [[ -f "${source}" ]]; then
  clean="./${source##*/}"
  clean="${target%.*}"
  echo "${clean} is a file."
  if [[ ! "${target}" ]]; then
    target="./${clean}/${clean}"
  fi
  poster_cmd="-ss 00:00:00 -vframes 1 ${target}/poster.jpg"
  echo -e "Executing command:\n/usr/local/Cellar/ffmpeg/4.2.2/bin/ffmpeg ${misc_params} -i ${source} ${poster_cmd}"
  files+=(
  # input      output
    "${source} ${target}"
  )
else 
  echo "Usage $: bash convert.sh SOURCE_FILE [OUTPUT_DIRECTORY]" && exit 1
fi

for file in "${files[@]}"; do
  file="${file/[[:space:]]+/ }"
  input="$(echo ${file} | cut -d ' ' -f 1)"
  output="$(echo ${file} | cut -d ' ' -f 2)"
  mkdir -p ${output}
  key_frames_interval="$(echo `/usr/local/Cellar/ffmpeg/4.2.2/bin/ffprobe ${input} 2>&1 | grep -oE '[[:digit:]]+(.[[:digit:]]+)? fps' | grep -oE '[[:digit:]]+(.[[:digit:]]+)?'`*2 | bc || echo '')"
  key_frames_interval=${key_frames_interval:-50}
  key_frames_interval=$(echo `printf "%.1f\n" $(bc -l <<<"$key_frames_interval/10")`*10 | bc)
  key_frames_interval=${key_frames_interval%.*}
  static_params="-c:a aac -ar 48000 -c:v h264 -profile:v main -crf 20 -sc_threshold 0"
  static_params+=" -g ${key_frames_interval} -keyint_min ${key_frames_interval} -hls_time ${segment_target_duration}"
  static_params+=" -hls_playlist_type vod"
  master_playlist="#EXTM3U
  #EXT-X-VERSION:3
  "
  cmd=""
  for rendition in "${renditions[@]}"; do
    rendition="${rendition/[[:space:]]+/ }"
    resolution="$(echo ${rendition} | cut -d ' ' -f 1)"
    bitrate="$(echo ${rendition} | cut -d ' ' -f 2)"
    audiorate="$(echo ${rendition} | cut -d ' ' -f 3)"
    width="$(echo ${resolution} | grep -oE '^[[:digit:]]+')"
    height="$(echo ${resolution} | grep -oE '[[:digit:]]+$')"
    maxrate="$(echo "`echo ${bitrate} | grep -oE '[[:digit:]]+'`*${max_bitrate_ratio}" | bc)"
    bufsize="$(echo "`echo ${bitrate} | grep -oE '[[:digit:]]+'`*${rate_monitor_buffer_ratio}" | bc)"
    bandwidth="$(echo ${bitrate} | grep -oE '[[:digit:]]+')000"
    name="${height}p"
    cmd+=" ${static_params} -vf scale=w=${width}:h=${height}:force_original_aspect_ratio=decrease"
    cmd+=" -b:v ${bitrate} -maxrate ${maxrate%.*}k -bufsize ${bufsize%.*}k -b:a ${audiorate}"
    cmd+=" -hls_segment_filename ${output}/${name}_%03d.ts ${output}/${name}.m3u8"
    master_playlist+="#EXT-X-STREAM-INF:BANDWIDTH=${bandwidth},RESOLUTION=${resolution}\n${name}.m3u8\n"
  done
  echo -e "Executing command:\n/usr/local/Cellar/ffmpeg/4.2.2/bin/ffmpeg ${misc_params} -i ${input} ${cmd}"
  /usr/local/Cellar/ffmpeg/4.2.2/bin/ffmpeg ${misc_params} -i ${input} ${cmd}
  echo -e "${master_playlist}" > ${output}/playlist.m3u8
  echo "Done - encoded HLS is at ${output}/"
done
