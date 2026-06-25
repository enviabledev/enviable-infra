data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_instance" "this" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = "t3.micro"
  subnet_id              = var.public_subnet_id
  vpc_security_group_ids = [var.ec2_security_group_id]
  iam_instance_profile   = var.instance_profile_name

  user_data = templatefile("${path.module}/userdata.sh.tftpl", {})

  root_block_device {
    volume_type = "gp3"
    volume_size = 40
    encrypted   = true
  }

  tags = { Name = "${var.project}-backend" }
}

resource "aws_eip" "this" {
  domain   = "vpc"
  instance = aws_instance.this.id
  tags     = { Name = "${var.project}-eip" }
}
