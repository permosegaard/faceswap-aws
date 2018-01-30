const fs = require("fs");

const tempcredscontents = fs.readFileSync("../files/awscreds.txt").toString().split("\n");

const Config = {
	AMAZON: {
		ACCESSKEY: tempcredscontents[0],
		SECRET: tempcredscontents[1],
		TYPE: "p2.xlarge",
		
		REGION: "us-east-1",
		AMI: "ami-4f1d2a35" // NOTE: p2.xlarge
		
		//REGION: "us-west-2",
		//AMI: "ami-38c87440" // NOTE: p2.xlarge
	}
};


const sleep = require("sleep");

const aws = require("aws-sdk");
aws.config.update({ accessKeyId: Config.AMAZON.ACCESSKEY, secretAccessKey: Config.AMAZON.SECRET, region: Config.AMAZON.REGION });

const ec2 = new aws.EC2();


async function awsrequest(_function, _params) {
	return _function.bind(ec2, _params)().promise().then(
		(data) => data, (error) => console.error(error, error.stack)
	);
}

async function create() {
	const publickey = fs.readFileSync("../files/id_rsa.pub").toString().split("\n")[0];
	
	const userdata = [
		`#cloud-config`,
		`repo_upgrade: none`,
		`runcmd:`,
		[ ` - [ "sh", "-c", "echo '`, publickey, `' > /root/.ssh/authorized_keys" ]` ].join(""),
		` - [ "sh", "-c", "chmod 600 /root/.ssh/authorized_keys" ]`
	].join("\n");
	
	const spotrequest = await awsrequest(
		ec2.requestSpotInstances,
		{
			InstanceCount: 1, Type: "one-time",
			LaunchSpecification: {
				ImageId: Config.AMAZON.AMI,
				InstanceType: Config.AMAZON.TYPE,
				UserData: new Buffer(userdata).toString("base64")
			}
		}
	);
	const spotrequestid = spotrequest.SpotInstanceRequests[0].SpotInstanceRequestId;
	
	let instanceid = "";
	
	while (true) {
		const temprequests = await awsrequest(ec2.describeSpotInstanceRequests, { SpotInstanceRequestIds: [ spotrequestid ] });
		const temprequest = temprequests.SpotInstanceRequests[0];
		
		if (temprequest.State === "active") { instanceid = temprequest.InstanceId; break; }
		
		sleep.sleep(30);
	}
	
	while (true) {
		const tempinstances = await awsrequest(ec2.describeInstances, { InstanceIds: [ instanceid ] });
		const tempinstance = tempinstances.Reservations[0].Instances[0];
		
		if (tempinstance.State.Name === "running") { return spotrequestid; }
		
		sleep.sleep(30);
	}
}

async function get_ip(_requestid) {
	const requests = await awsrequest(ec2.describeSpotInstanceRequests, { SpotInstanceRequestIds: [ _requestid ] });
	const instances = await awsrequest(ec2.describeInstances, { InstanceIds: [ requests.SpotInstanceRequests[0].InstanceId ] });
	const instance = instances.Reservations[0].Instances[0];
	
	return instance.PublicIpAddress;
}

async function terminate(_requestid) {
	await awsrequest(ec2.cancelSpotInstanceRequests, { SpotInstanceRequestIds: [ _requestid ] });
}

(
	async () => {
		try {
			switch (process.argv[2]) {
				case "create":
					console.log(await create());
					break;
					
				case "get_ip":
					console.log(await get_ip(process.argv[3]));
					break;
					
				case "terminate":
					await terminate(process.argv[3]);
					break;
					
				default:
					console.error("bad args");
					process.exit(1);
			}
			
			process.exit();
		}
		catch (exception) {
			console.error(exception);
			process.exit(1);
		}
	}
)();
