provider "aws" {
  region                  = "us-east-1"
  shared_credentials_files = ["~/.aws/credentials"]
}

# Generate SSH Key Pair
resource "tls_private_key" "healthcare_key" {
  algorithm = "RSA"
}

resource "aws_key_pair" "healthcare_key" {
  key_name   = "healthcare_key"
  public_key = tls_private_key.healthcare_key.public_key_openssh

  provisioner "local-exec" {
    command = "echo '${tls_private_key.healthcare_key.private_key_pem}' > ./healthcare-key.pem"
  }
}

# Create VPC
resource "aws_vpc" "HEALTHCARE_VPC" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"

  tags = {
    Name = "HEALTHCARE-VPC"
  }
}

# Create Subnet
resource "aws_subnet" "HEALTHCARE_SUBNET" {
  vpc_id     = aws_vpc.HEALTHCARE_VPC.id
  cidr_block = "10.0.1.0/24"

  tags = {
    Name = "HEALTHCARE-SUBNET"
  }
}

# Create Internet Gateway
resource "aws_internet_gateway" "HEALTHCARE_igw" {
  vpc_id = aws_vpc.HEALTHCARE_VPC.id

  tags = {
    Name = "HEALTHCARE-IGW"
  }
}

# Create Route Table
resource "aws_route_table" "HEALTHCARE_route_table" {
  vpc_id = aws_vpc.HEALTHCARE_VPC.id

  tags = {
    Name = "HEALTHCARE-route-table"
  }
}

# Add Route to Internet Gateway
resource "aws_route" "default_route" {
  route_table_id         = aws_route_table.HEALTHCARE_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.HEALTHCARE_igw.id
}

# Associate Route Table with Subnet
resource "aws_route_table_association" "HEALTHCARE_route_table_association" {
  subnet_id      = aws_subnet.HEALTHCARE_SUBNET.id
  route_table_id = aws_route_table.HEALTHCARE_route_table.id
}

# Define Security Group Ports
variable "HEALTHCARE_ports" {
  type    = list(number)
  default = [22, 80, 443, 8080]
}

# Create Security Group
resource "aws_security_group" "HEALTHCARE_sg" {
  name   = "HEALTHCARE_rule"
  vpc_id = aws_vpc.HEALTHCARE_VPC.id

  # Ingress Rules
  dynamic "ingress" {
    for_each = var.HEALTHCARE_ports
    content {
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  # Egress Rules
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create EC2 Instance

resource "aws_instance" "Master" {
  ami                         = "ami-005fc0f236362e99f"
  instance_type               = "t2.medium"
  key_name                    = aws_key_pair.healthcare_key.key_name
  subnet_id                   = aws_subnet.HEALTHCARE_SUBNET.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.HEALTHCARE_sg.id]

  tags = {
    Name = "Master"
  }

  # Remote Exec Provisioner
  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = tls_private_key.healthcare_key.private_key_pem
      host        = self.public_ip
      timeout     = "5m"
    }

    inline = [
      "sudo apt update",
      "sudo apt install -y software-properties-common",
      "sudo add-apt-repository --yes --update ppa:ansible/ansible",
      "sudo apt install -y ansible"
    ]
  }
}

resource "aws_instance" "Worker" {
  ami                         = "ami-005fc0f236362e99f"
  instance_type               = "t2.micro"
  count                       = 2 
  key_name                    = aws_key_pair.healthcare_key.key_name
  subnet_id                   = aws_subnet.HEALTHCARE_SUBNET.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.HEALTHCARE_sg.id]

  tags = {
    Name = "Worker-${count.index + 1}"
  }

   # Remote Exec Provisioner
  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = tls_private_key.healthcare_key.private_key_pem
      host        = self.public_ip
      timeout     = "5m"
    }

    inline = [
      "sudo apt update",
      "sudo apt install -y openjdk-17-jdk"
    ]
  }
}