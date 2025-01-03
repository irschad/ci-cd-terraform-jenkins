
### 1. **Create SSH Keypair**

To securely access AWS instances, you need to create an SSH keypair.

- **Generate SSH Keypair via AWS Console:**
    1. Log in to the AWS Management Console and go to the **EC2 Dashboard**.
    2. Under **Network & Security**, select **Key Pairs**.
    3. Click on **Create Key Pair**.
    4. Name the key pair `myapp-key-pair` and select the **PEM format**.
    5. Click **Create Key Pair**.
    6. The PEM file will be automatically downloaded to your machine. **Store it securely**, as it will be needed later.

- **Share the PEM File with Jenkins:**
    1. Log in to your Jenkins server.
    2. In Jenkins, go to **Manage Jenkins** → **Manage Credentials**.
    3. Select the appropriate domain or use **(global)**.
    4. Click **(Add Credentials)**.
    5. In the **Kind** dropdown, select **SSH Username with private key**.
    6. Enter `server-ssh-key` as the **ID**.
    7. Set the **Username** to `ec2-user`.
    8. Select **Enter directly** under **Private Key**.
    9. Open the downloaded PEM file, copy its contents, and paste it into the **Private Key** field.
    10. Click **Create**.

Now, Jenkins will be able to access EC2 instances via SSH using this private key.

- **Add the Key Pair to EC2 Instance in Terraform:**
    - In your Terraform configuration for the EC2 instance, reference the `myapp-key-pair` you created:
    ```hcl
    resource "aws_instance" "my_instance" {
      ami           = "ami-0c55b159cbfafe1f0"
      instance_type = "t2.micro"
      key_name      = "myapp-key-pair"

      tags = {
        Name = "MyInstance"
      }
    }
    ```
    This will associate the key pair with the EC2 instance, allowing Jenkins to SSH into it using the PEM private key.



### 2. **Install Terraform Inside Jenkins Container**

To use Terraform within Jenkins, you'll need to install it inside the Jenkins container.

- **SSH into the Jenkins Container:**
    1. First, find the Jenkins container's ID by running the following command:
       ```bash
       docker ps
       ```
    2. SSH into the Jenkins container as a root user:
       ```bash
       docker exec -it -u 0 <container-id> bash
       ```

- **Check the Operating System:**
    Once inside the Jenkins container, check the operating system:
    ```bash
    cat /etc/os-release
    ```

- **Install Terraform:**
    To install Terraform, use the following steps:
    1. Add the HashiCorp GPG key:
       ```bash
       wget -O- https://apt.releases.hashicorp.com/gpg | \
       gpg --dearmor | \
       tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null
       ```
    2. Add the HashiCorp repository:
       ```bash
       echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
       https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
       tee /etc/apt/sources.list.d/hashicorp.list
       ```
    3. Update the package list and install Terraform:
       ```bash
       apt update && apt install terraform
       ```

- **Check Terraform Version:**
    After installation, verify that Terraform is installed correctly:
    ```bash
    terraform -v
    ```
    This should display the installed version of Terraform.


### 3. Configure S3 Backend 

#### Steps to Configure the S3 Backend

1. **Create an S3 Bucket**  
   Log in to the AWS Management Console and create an S3 bucket named `myapp-tf-s3-bucket9` in the `us-east-1` region.

2. **Enable Versioning**  
   Navigate to the bucket settings and enable versioning. This ensures a history of state files is maintained for recovery purposes.

3. **Disable Bucket Key**  
   In the bucket's encryption settings, disable the bucket key option to ensure encryption uses only the default AWS S3-managed keys.

4. **Update Terraform Configuration**  
   Add the following `terraform` block to your Terraform configuration file to specify the S3 backend:

   ```hcl
   terraform {
     required_version = ">= 0.12"
     backend "s3" {
       bucket = "myapp-tf-s3-bucket9"
       key    = "myapp/state.tfstate"
       region = "us-east-1"
     }
   }
   ```

## Notes
- **Bucket Naming**: Ensure the bucket name is unique across all AWS accounts.
- **IAM Permissions**: The IAM role or user running Terraform must have permissions to access the S3 bucket and its objects.



### 4. **Create Terraform Configuration to Provision Server**

Inside your project directory, create a `terraform` folder and then create the `main.tf` file with the following configuration:

#### **`main.tf` Configuration:**

```hcl
terraform {
  required_version = ">= 0.12"
  backend "s3" {
    bucket = "myapp-tf-s3-bucket9"
    key    = "myapp/state.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  region = var.region
}

resource "aws_vpc" "myapp-vpc" {
  cidr_block = var.vpc_cidr_block
  tags = {
    Name = "${var.env_prefix}-vpc"
  }
}

resource "aws_subnet" "myapp-subnet-1" {
  vpc_id            = aws_vpc.myapp-vpc.id
  cidr_block        = var.subnet_cidr_block
  availability_zone = var.avail_zone
  tags = {
    Name = "${var.env_prefix}-subnet-1"
  }
}

resource "aws_internet_gateway" "myapp-igw" {
  vpc_id = aws_vpc.myapp-vpc.id
  tags = {
    Name = "${var.env_prefix}-igw"
  }
}

resource "aws_default_route_table" "main-rtb" {
  default_route_table_id = aws_vpc.myapp-vpc.default_route_table_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.myapp-igw.id
  }

  tags = {
    Name = "${var.env_prefix}-main-rtb"
  }
}

resource "aws_default_security_group" "default-sg" {
  vpc_id = aws_vpc.myapp-vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "TCP"
    cidr_blocks = [var.my_ip, var.jenkins_ip]
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    prefix_list_ids = []
  }

  tags = {
    Name = "${var.env_prefix}-default-sg"
  }
}

data "aws_ami" "latest-amazon-linux-image" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-kernel-*-x86_64-gp2"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "myapp-server" {
  ami                   = data.aws_ami.latest-amazon-linux-image.id
  instance_type         = var.instance_type
  subnet_id             = aws_subnet.myapp-subnet-1.id
  vpc_security_group_ids = [aws_default_security_group.default-sg.id]
  availability_zone     = var.avail_zone
  associate_public_ip_address = true
  key_name             = "myapp-key-pair"
  user_data            = file("entry-script.sh")
  user_data_replace_on_change = true

  tags = {
    Name = "${var.env_prefix}-server"
  }
}

output "ec2-public_ip" {
  value = aws_instance.myapp-server.public_ip
}
```

Add entry-script.sh File:
This script will be used to install Docker and Docker Compose while provisioning the EC2 instance:

```bash
#!/bin/bash
sudo yum update -y && sudo yum install -y docker
sudo systemctl start docker
sudo usermod -aG docker ec2-user

# Install Docker Compose
sudo curl -SL "https://github.com/docker/compose/releases/download/v2.20.3/docker-compose-linux-x86_64" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
```

Create variables.tf File:
Define your variables in the variables.tf file:
```hcl

variable "vpc_cidr_block" {
  default = "10.0.0.0/16"
}

variable "subnet_cidr_block" {
  default = "10.0.10.0/24"
}

variable "avail_zone" {
  default = "us-east-1a"
}

variable "env_prefix" {
  default = "dev"
}

variable "my_ip" {
  default = "110.225.86.108/32"
}

variable "jenkins_ip" {
  default = "54.221.99.206/32"
}

variable "instance_type" {
  default = "t2.micro"
}

variable "region" {
  default = "us-east-1"
}
```

### 5. **Update `Jenkinsfile` for Provisioning and Deploy Stages**

Update the `Jenkinsfile` to include a **provision stage** and a **deploy stage** as described below:

#### **Add Provision Stage:**

Add a new `provision server` stage before the `deploy` stage:

```groovy
stage("provision server") {
  environment {
    AWS_ACCESS_KEY_ID = credentials('jenkins_aws_access_key_id')
    AWS_SECRET_ACCESS_KEY = credentials('jenkins_aws_secret_access_key')
    TF_VAR_env_prefix = 'test'
  }
  steps {
    script {
      dir('terraform') {
        sh "terraform init"
        sh "terraform apply --auto-approve"
        EC2_PUBLIC_IP = sh(
          script: "terraform output ec2-public_ip",
          returnStdout: true
        ).trim()
      }
    }
  }
}
```

Key Changes:
The TF_VAR_env_prefix is used to set the env_prefix variable inside Terraform dynamically.
The ec2-public_ip output from Terraform is captured and assigned to the EC2_PUBLIC_IP environment variable for use in the deploy stage.

Add Deploy Stage:
Include a deploy stage to handle deployment tasks:

```groovy
stage("deploy") {
  environment {
    DOCKER_CREDS = credentials('docker-hub-repo')
  }
  steps {
    script {
      echo "waiting for EC2 server to initialize"
      sleep(time: 90, unit: "SECONDS")

      echo 'deploying docker image to EC2...'
      echo "${EC2_PUBLIC_IP}"
      
      def shellCmd = "bash ./server-cmds.sh ${IMAGE_NAME} ${DOCKER_CREDS_USR} ${DOCKER_CREDS_PSW}"
      def ec2Instance = "ec2-user@${EC2_PUBLIC_IP}"

      sshagent(['server-ssh-key']) {
        sh "scp -o StrictHostKeyChecking=no server-cmds.sh ${ec2Instance}:/home/ec2-user"
        sh "scp -o StrictHostKeyChecking=no docker-compose.yaml ${ec2Instance}:/home/ec2-user"
        sh "ssh -o StrictHostKeyChecking=no ${ec2Instance} ${shellCmd}"
      }
    }
  }
}
```

Key Changes:
A 90-second sleep is introduced to allow the EC2 instance to initialize before deployment.
Strict host key checking is disabled (-o StrictHostKeyChecking=no) for scp and ssh commands to ensure smooth execution.

Deployment commands:
Transfer required files (server-cmds.sh and docker-compose.yaml) to the EC2 instance using scp.
Execute the deployment script remotely on the EC2 instance using ssh.

 
### 6. Run the Jenkins pipeline and check deployment:
     
   Commit the code to GitHub repository.
   Run the Jenkins pipeline.
   View the console output and observe the following:
   - Docker build and push stages output
   - AWS provider initialization and s3 backend initialization with terraform init 
   - terraform apply output
   - SSH agent steps
   - Pulling of docker images, containers creation and start

   View state of terraform configuration:
   ```hcl
   terraform state list
   ```
   Go to S3 in AWS Console and see tf state file present there now in the bucket "myapp-tf-s3-backend9"
   
   SSH into the EC2 instance and check the container running:
   ```bash
   docker ps
   ```
   Access the java maven application from web browser:
   http://ec2-ip-address:8000/
   


   
