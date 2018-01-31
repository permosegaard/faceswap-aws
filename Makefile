sshopts=-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ./files/id_rsa
instanceip=$(shell cat ./run/instance_ip)
sshcommand=ssh $(sshopts) root@$(instanceip)

.PHONY: check-deps clean keygen pre-run run debug instance-ssh instance-ps instance-top instance-du instance-nsmi

check-deps:
	which ssh
	which ssh-keygen
	which rsync
	which timeout
	which node
	which npm
	npm update

clean:
	@rm -Rf ./run/*; mkdir -p ./run/in/{source,destination}

keygen:
	@cd ./files/; rm -f id_rsa*; ssh-keygen -t rsa -N "" -f id_rsa; cd ..

pre-run: check-deps clean keygen

debug:
	@cd ./run/; bash -x ../code/swapper.sh; cd ..

run:
	@cd ./run/; bash ../code/swapper.sh; cd ..

vr:
	@cd ./run/; bash ../code/swapper.sh vr; cd ..


download-preview:
	@rsync -e "ssh $(sshopts)" root@$(instanceip):/root/faceswap/_sample.jpg ./run/
	@which xdg-open > /dev/null && xdg-open ./run/_sample.jpg

instance-ssh:
	@$(sshcommand)

instance-ps:
	$(sshcommand) "ps auxf"

instance-top:
	$(sshcommand) "top -b -n1"

instance-du:
	$(sshcommand) "du -sh /root/faceswap"

instance-nsmi:
	$(sshcommand) "nvidia-smi"
