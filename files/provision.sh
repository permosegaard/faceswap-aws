#set -e # NOTE: broken :(

DEBIAN_FRONTEND=noninteractive apt install -y python3-venv ffmpeg

cd ~/
git clone https://github.com/deepfakes/faceswap.git
python3 -m venv ./faceswap/

cd ./faceswap
./bin/pip3 install -r ./requirements-gpu.txt
mkdir -p ./run/in/video/ ./run/processed/{source,destination,video,model}/ ./run/out/
