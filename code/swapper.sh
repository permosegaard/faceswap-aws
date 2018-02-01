training_timeout="0" # NOTE: syntax from timeout command ie. "6h" for 6 hours, 0 for manual control
training_batch="16" # NOTE: must be multiple of 2 and 16 or above, default=64
training_save="500" # NOTE: iterations per save greater thans 0 as multiple of 10, iterations take ~1s on p2.xlarge
download_convert_model=true # NOTE: true = download trained model, false = do not download
download_convert_extra=false # NOTE: true = download final video and stills from conversion - will take time, false = download final video only
terminate_spot_on_finish=true # NOTE: true = cancel spot request and terminate instance automatically when done


echo "$(date): creating..."
requestid="$(node ../code/aws.js create)"
if [ $? -ne 0 ]; then exit 1; fi

ip="$(node ../code/aws.js get_ip ${requestid})"
if [ $? -ne 0 ]; then exit 1; fi
echo "${ip}" > ./instance_ip

sshopts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ../files/id_rsa"
sshcmd="ssh ${sshopts} root@${ip}"


echo; echo; echo "$(date): waiting for ssh..."
while sleep 10
do
	if timeout 10s ${sshcmd} "echo BLAH" 2>/dev/null | grep -q "BLAH"; then break; fi
done


echo; echo; echo "$(date): waiting for automatic updates..."
sleep 30 && while sleep 10
do
	if ${sshcmd} "/usr/bin/unattended-upgrade --dry-run" 1>/dev/null 2>&1; then break; fi
done


echo; echo; echo "$(date): provisioning..."
${sshcmd} -t < ../files/provision.sh


echo; echo; echo "$(date): uploading..."
rsync -a -e "ssh ${sshopts}" --info=progress2 ../run root@${ip}:/root/faceswap/


echo; echo; echo "$(date): extracting..."
for i in "source" "destination"
do
	${sshcmd} "cd /root/faceswap; LD_LIBRARY_PATH=/usr/local/cuda-8.0/lib64 ./bin/python3 faceswap.py extract -i ./run/in/${i} -o ./run/processed/${i}"
done


echo; echo; echo "$(date): training..."
${sshcmd} "cd /root/faceswap; sed -i 's/BATCH_SIZE = [0-9]*/BATCH_SIZE = ${training_batch}/' ./scripts/train.py"
if [ -d ./run/in/model ]; then ${sshcmd} "cd /root/faceswap; cp -Ra ./run/in/model* ./run/processed/model/"; fi
if [ "${training_timeout}" = "0" ]
then
	${sshcmd} "cd /root/faceswap; LD_LIBRARY_PATH=/usr/local/cuda-8.0/lib64 ./bin/python3 faceswap.py train -w -s ${training_save} -m ./run/processed/model/ -A ./run/processed/source/ -B ./run/processed/destination/; exit"
else
	${sshcmd} "cd /root/faceswap; LD_LIBRARY_PATH=/usr/local/cuda-8.0/lib64 timeout ${training_timeout} ./bin/python3 faceswap.py train -w -s${training_save} -m ./run/processed/model/ -A ./run/processed/source/ -B ./run/processed/destination/"
fi


echo; echo; echo "$(date): converting..."
if [ "${1}" = "vr" ]
then
	${sshcmd} "cd /root/faceswap; ffmpeg -i ./run/in/video.mp4 -filter_complex 'split[l][r];[l]stereo3d=sbsl:ml[left];[r]stereo3d=sbsl:mr[right]' -map [left] -map 0:a -c:a copy ./run/in/video-left.mp4 -map [right] -map 0:a -c:a copy ./run/in/video-right.mp4"
	for i in "left" "right"; do ${sshcmd} "cd /root/faceswap; ffmpeg -i './run/in/video-${i}.mp4' './run/in/video/frame-${i}-%06d.png'"; done
	${sshcmd} "cd /root/faceswap; LD_LIBRARY_PATH=/usr/local/cuda-8.0/lib64 ./bin/python3 faceswap.py convert -m ./run/processed/model/ -i ./run/in/video/ -o ./run/processed/video/"
	for i in "left" "right"; do ${sshcmd} "cd /root/faceswap; ffmpeg -pattern_type glob -i './run/processed/video/frame-${i}-*.png' -c:v libx264 -vf 'fps=25,format=yuv420p' ./run/processed/video-${i}.mp4"; done
	${sshcmd} "cd /root/faceswap; ffmpeg -i ./run/processed/video-left.mp4 -i ./run/processed/video-right.avi -filter_complex 'hstack,format=yuv420p' -c:v libx264 -crf 18 ./run/out/video.mp4"
else
	${sshcmd} "cd /root/faceswap; ffmpeg -i './run/in/video.mp4' './run/in/video/frame-%06d.png'"
	${sshcmd} "cd /root/faceswap; LD_LIBRARY_PATH=/usr/local/cuda-8.0/lib64 ./bin/python3 faceswap.py convert -m ./run/processed/model/ -i ./run/in/video/ -o ./run/processed/video/"
	${sshcmd} "cd /root/faceswap; ffmpeg -pattern_type glob -i './run/processed/video/frame-*.png' -c:v libx264 -vf 'fps=25,format=yuv420p' ./run/out/video.mp4"
fi


echo; echo; echo "$(date): downloading..."
if [ "${download_convert_extra}" = true ]
then
	rsync -a -e "ssh ${sshopts}" --info=progress2 root@${ip}:/root/faceswap/run/{out,processed} ../run/
elif [ "${download_convert_model}" = true ]
then
	mkdir -p ../run/processed; 
	rsync -a -e "ssh ${sshopts}" --info=progress2 root@${ip}:/root/faceswap/run/out ../run/
	rsync -a -e "ssh ${sshopts}" --info=progress2 root@${ip}:/root/faceswap/run/processed/model ../run/processed/
else
	rsync -a -e "ssh ${sshopts}" --info=progress2 root@${ip}:/root/faceswap/run/out/video.mp4 ../run/out/
fi


echo; echo; echo "$(date): terminating..."
if [ "$(terminate_spot_on_finish)" = true ]
then
	node ../code/aws.js terminate ${requestid}
else
	echo; echo "*** not terminating instance automatically, remember to do this yourself! ***"
fi
rm -f ./instance_ip


echo; echo; echo "$(date): finished!"
echo -e "\a" # NOTE: terminal bell
