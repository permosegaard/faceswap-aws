training_timeout="0" # NOTE: syntax from timeout command ie. "6h" for 6 hours, 0 for manual control
training_batch="16" # NOTE: must be multiple of 2 and 16 or above, default=64
training_save="500" # NOTE: iterations per save greater thans 0 as multiple of 10, iterations take ~1s on p2.xlarge
download_convert_extra=false # NOTE: true = copy final video and stills from conversion - will take time, false = copy final video only
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
if [ "${training_timeout}" = "0" ]
then
	${sshcmd} "cd /root/faceswap; LD_LIBRARY_PATH=/usr/local/cuda-8.0/lib64 ./bin/python3 faceswap.py train -w -s ${training_save} -m ./run/processed/model/ -A ./run/processed/source/ -B ./run/processed/destination/; exit"
else
	${sshcmd} "cd /root/faceswap; LD_LIBRARY_PATH=/usr/local/cuda-8.0/lib64 timeout ${training_timeout} ./bin/python3 faceswap.py train -w -s${training_save} -m ./run/processed/model/ -A ./run/processed/source/ -B ./run/processed/destination/"
fi


echo; echo; echo "$(date): converting..."
${sshcmd} "cd /root/faceswap; ffmpeg -i './run/in/video.mp4' './run/in/video/frame-%06d.png'"
${sshcmd} "cd /root/faceswap; LD_LIBRARY_PATH=/usr/local/cuda-8.0/lib64 ./bin/python3 faceswap.py convert -m ./run/processed/model/ -i ./run/in/video/ -o ./run/processed/video/"
${sshcmd} "cd /root/faceswap; ffmpeg -pattern_type glob -i './run/processed/video/frame-*.png' -c:v libx264 -vf 'fps=25,format=yuv420p' ./run/out/video.mp4"


echo; echo; echo "$(date): downloading..."
if [ "${download_convert_extra}" = true ]
then
	rsync -a -e "ssh ${sshopts}" --info=progress2 root@${ip}:/root/faceswap/run/{out/,converted/} ../run/
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
