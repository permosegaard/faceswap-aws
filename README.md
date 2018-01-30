# faceswap-aws

## automatically run faceswap on a gpu instance in aws


### requirements
1. "make check-deps" in repo root for basic binaries check, install anything that's missing per your distribution docs
2. "make keygen" in repo root to generate public/private keypair for instance ssh
3. replace contents of files/awscreds.txt with aws api credentials


### usage 
1. place images of face to overlay in "run/in/source/"
2. please images of face to be replaced in "run/in/destination/"
3. place video/clip to alter in run/in/video.m4a
4. "make run" to start the process
5. wait for training to complete via timeout (see code/swapper.sh) or press ctrl+c when happy with training results (use "make download-preview" in project root to download current training sample to ./run/)
6. wait for process to complete, this can take some time depending on options used, transfer bandwidth available. etc.
7. *** CHECK THE INSTANCE HAS BEEN COMPLETLY DESTROYED IN AWS CONSOLE TO PREVENT UNWANTED CHARGES ***



### example replacing nic cage as neo in the matrix 
1. place images of nic cage in "run/in/source"
2. place images of keanu in "run/in/destination"
3. please video clip in "run/in/video.mp4"



### notes 
 - images for training you should be a sizeable amount of well lit, unobstrcuted (glasses/hair/etc.) and generally similar looking for best results
 - training for more than 6 hours can hurt final results, if you're unsure see "make download-preview" to see how training's going
 - simple config changes available at the tops of code/swapper.sh and code/aws.js that may be useful inc. debug & automation options
