#!/bin/bash

#############################################
# Basic commands to create VPC and instance
#
# Jose Moreno, March 2022
#############################################

# Variables
sg_name=myvmsg
kp_name=joseaws
instance_size='t2.nano'
instance_image=ami-'059cd2be9c27a0e81'
# instance_image=ami-a4827dc9
vpc_prefix='z.0.0/16'
subnet1_prefix='192.168.1.0/24'
subnet2_prefix='192.168.2.0/24'

# Docs:
# https://www.studytrails.com/2016/11/09/create-aws-ec2-instance-using-cli/

# Get Image
# https://opensourceconnections.com/blog/2015/07/27/advanced-aws-cli-jmespath-query/
# aws ec2 describe-images --owners amazon --filters "Name=image-type,Values=machine" --query 'Images[].[ImageId,Name]' --output text
# aws ec2 describe-images --owners amazon --filters "Name=image-type,Values=machine" --query 'Images[?Name!=`null`]|[?starts_with(Name,`Ubuntu_20`)].[ImageId,Name]' --output text
# aws ec2 describe-images --owners amazon --filters "Name=image-type,Values=machine" --query 'Images[?Name!=`null`]|[?starts_with(Name,`Cisco`)].[ImageId,Name]' --output text
# aws ec2 describe-images --owners amazon --filters "Name=image-type,Values=machine" --query 'Images[?Name!=`null`]|[?starts_with(Name,`Ubuntu_20`)]|[? !contains(Name,`SQL`)].[ImageId,Name]' --output text
# aws ec2 describe-images --owner amazon --query 'Images[?starts_with(ImageId, `ami-`)]|[0:5].[ImageId,Name]' --output text

# Create Key Pair if not there
kp_id=$(aws ec2 describe-key-pairs --key-name $kp_name --query 'KeyPairs[0].KeyPairId' --output text)
if [[ -z "$kp_id" ]]; then
    echo "Key pair $kp_name does not exist, creating new..."
    pemfile="$HOME/.ssh/${kp_name}.pem"
    touch "$pemfile"
    aws ec2 create-key-pair --key-name $kp_name --key-type rsa --query 'KeyMaterial' --output text > $pemfile
    chmod 400 "$pemfile"
else
    echo "Key pair $kp_name already exists with ID $kp_id"
fi

# VPC and subnet
# https://docs.aws.amazon.com/vpc/latest/userguide/vpc-subnets-commands-example.html
vpc_id=$(aws ec2 create-vpc --cidr-block "$vpc_prefix" --query Vpc.VpcId --output text)
zone1_id=$(aws ec2 describe-availability-zones --query 'AvailabilityZones[0].ZoneId' --output text)
zone2_id=$(aws ec2 describe-availability-zones --query 'AvailabilityZones[1].ZoneId' --output text)
subnet1_id=$(aws ec2 create-subnet --vpc-id "$vpc_id" --cidr-block "$subnet1_prefix" --availability-zone-id "$zone1_id" --query Subnet.SubnetId --output text)
subnet2_id=$(aws ec2 create-subnet --vpc-id "$vpc_id" --cidr-block "$subnet2_prefix" --availability-zone-id "$zone2_id" --query Subnet.SubnetId --output text)
igw_id=$(aws ec2 create-internet-gateway --query InternetGateway.InternetGatewayId --output text)
if [[ -n "$igw_id" ]]; then
    aws ec2 attach-internet-gateway --vpc-id "$vpc_id" --internet-gateway-id "$igw_id"
fi
aws ec2 modify-subnet-attribute --subnet-id "$subnet1_id" --map-public-ip-on-launch
aws ec2 modify-subnet-attribute --subnet-id "$subnet2_id" --map-public-ip-on-launch

# Route table
rt_id=$(aws ec2 create-route-table --vpc-id "$vpc_id" --query RouteTable.RouteTableId --output text)
aws ec2 create-route --route-table-id "$rt_id" --destination-cidr-block 0.0.0.0/0 --gateway-id "$igw_id"
aws ec2 associate-route-table  --subnet-id "$subnet1_id" --route-table-id "$rt_id"
aws ec2 associate-route-table  --subnet-id "$subnet2_id" --route-table-id "$rt_id"

# If subnet and VPC already existed
vpc_id=$(aws ec2 describe-vpcs --filters "Name=cidr-block,Values=$vpc_prefix" --query 'Vpcs[0].VpcId' --output text)
subnet1_id=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc_id" "Name=cidr-block,Values=$subnet1_prefix" --query 'Subnets[0].SubnetId' --output text)
subnet2_id=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc_id" "Name=cidr-block,Values=$subnet2_prefix" --query 'Subnets[0].SubnetId' --output text)

# Create SG
aws ec2 create-security-group --group-name $sg_name --description "Test SG" --vpc-id "$vpc_id"
sg_id=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=$sg_name" --query 'SecurityGroups[0].GroupId' --output text)
aws ec2 authorize-security-group-ingress --group-id "$sg_id" --protocol tcp --port 22 --cidr 0.0.0.0/0

# Create instances
aws ec2 run-instances --image-id "$instance_image" --key-name "$kp_name" --security-group-ids "$sg_id" --instance-type "$instance_size" --subnet-id "$subnet1_id"
aws ec2 run-instances --image-id "$instance_image" --key-name "$kp_name" --security-group-ids "$sg_id" --instance-type "$instance_size" --subnet-id "$subnet2_id"
# aws ec2 run-instances  --image-id ami-5ec1673e --key-name MyKey --security-groups EC2SecurityGroup --instance-type t2.micro --placement AvailabilityZone=us-west-2b --block-device-mappings DeviceName=/dev/sdh,Ebs={VolumeSize=100} --count 2
instance1_id=$(aws ec2 describe-instances --filters "Name=subnet-id,Values=$subnet1_id" --query 'Reservations[0].Instances[0].InstanceId' --output text)
instance2_id=$(aws ec2 describe-instances --filters "Name=subnet-id,Values=$subnet2_id" --query 'Reservations[0].Instances[0].InstanceId' --output text)

# Check SSH access
instance1_pip=$(aws ec2 describe-instances --instance-id "$instance1_id" --query 'Reservations[*].Instances[*].PublicIpAddress' --output text) && echo "$instance1_pip"
instance2_pip=$(aws ec2 describe-instances --instance-id "$instance2_id" --query 'Reservations[*].Instances[*].PublicIpAddress' --output text) && echo "$instance2_pip"
pemfile="$HOME/.ssh/${kp_name}.pem"
user=ec2-user
ssh -n -o BatchMode=yes -o StrictHostKeyChecking=no -i "$pemfile" "${user}@${instance1_pip}" "ip a"
ssh -n -o BatchMode=yes -o StrictHostKeyChecking=no -i "$pemfile" "${user}@${instance2_pip}" "ip a"

###############
# Diagnostics #
###############

aws ec2 describe-security-groups --group-names "$sg_name"
aws ec2 describe-key-pairs

aws ec2 describe-vpcs --query 'Vpcs[].[VpcId,CidrBlock]' --output text
aws ec2 describe-vpcs --vpc-id "$vpc_id"
aws ec2 describe-subnets --query 'Subnets[].[SubnetId,VpcId,CidrBlock]' --output text
aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc_id"
aws ec2 describe-internet-gateways
aws ec2 describe-route-tables --query 'RouteTables[].[RouteTableId,VpcId]' --output text

aws ec2 describe-instances --query 'Reservations[*].Instances[*].[InstanceId,ImageId,PrivateIpAddress,Placement.AvailabilityZone,State.Name]' --output text

###############
#   Cleanup   #
###############

function delete_vpc() {
    vpc_id=$1
    # Look for IGW attachments
    igw_id=$(aws ec2 describe-internet-gateways --query 'InternetGateways[].{VpcId: Attachments[*].VpcId|[0], IgwId: InternetGatewayId}|[?VpcId==`'$vpc_id'`].IgwId|[0]' --output text)
    while [[ -n "$igw_id" ]] && [[ "$igw_id" != "None" ]]; do
        echo "Found attachment between IGW $igw_id and VPC $vpc_id. Detaching IGW..."
        aws ec2 detach-internet-gateway --vpc-id "$vpc_id" --internet-gateway-id "$igw_id"
        echo "Trying to delete IGW $igw_id..."
        aws ec2 delete-internet-gateway --internet-gateway-id "$igw_id"
        igw_id=$(aws ec2 describe-internet-gateways --query 'InternetGateways[].{VpcId: Attachments[*].VpcId|[0], IgwId: InternetGatewayId}|[?VpcId==`'$vpc_id'`].IgwId|[0]' --output text)
    done
    # Look for subnets
    subnet_id=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc_id" --query 'Subnets[0].SubnetId' --output text)
    while [[ -n "$subnet_id" ]] && [[ "$subnet_id" != "None" ]]; do
        echo "Found subnet $subnet_id in VPC $vpc_id. Trying to delete subnet now..."
        aws ec2 delete-subnet --subnet-id "$subnet_id"
        subnet_id=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc_id" --query 'Subnets[0].SubnetId' --output text)
    done
    # Look for a RT associated to this VPC
    rt_id=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$vpc_id" --query 'RouteTables[0].RouteTableId' --output text)
    previous_rt_id=""       # We keep track of the last route table ID
    while [[ -n "$rt_id" ]] && [[ "$rt_id" != "None" ]] && [[ "$rt_id" != "$previous_rt_id" ]]; do
        echo "Found Route Table $rt_id in VPC $vpc_id. Looking for associations..."
        # Disassociating RT first...
        ass_id_list=$(aws ec2 describe-route-tables --route-table-id $rt_id --query 'RouteTables[0].Associations[].RouteTableAssociationId' --output text)
        i=1
        ass_id=$(echo "$ass_id_list" | cut -f $i)
        previous_ass_id=""      # We keep count of the previous association ID, because single count results doesnt seem to work fine with cut, and `echo $ass_id_list | cut -f x` will always return the same, regardless x
        while [[ -n $ass_id ]] && [[ "$ass_id" != "$previous_ass_id" ]]; do
            echo "Deleting route table association ID $i: $ass_id..."
            aws ec2 disassociate-route-table --association-id "$ass_id"
            i=$(( i + 1 ))
            previous_ass_id=$ass_id
            ass_id=$(echo "$ass_id_list" | cut -f $i)
        done
        # Delete routes
        # Delete RT
        echo "Deleting route table $rt_id now..."
        aws ec2 delete-route-table --route-table-id "$rt_id"
        previous_rt_id="$rt_id"
        rt_id=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$vpc_id" --query 'RouteTables[0].RouteTableId' --output text)
    done
    # Delete VPC
    echo "Trying to delete VPC $vpc_id..."
    aws ec2 delete-vpc --vpc-id "$vpc_id"
}

function delete_all_sgs() {
    sg_list=$(aws ec2 describe-security-groups --query 'SecurityGroups[*].[GroupId]' --output text)
    while read -r sg_id
    do
        echo "Deleting SG ${sg_id}..."
        aws ec2 delete-security-group --group-id "$sg_id"
    done < <(echo "$sg_list")
}

function delete_all_instances() {
    instance_list=$(aws ec2 describe-instances --query 'Reservations[*].Instances[*].[InstanceId]' --output text)
    while read -r instance_id
    do
        echo "Terminating instance ${instance_id}..."
        aws ec2 terminate-instances --instance-ids "${instance_id}"
    done < <(echo "$instance_list")
}

delete_all_instances
delete_all_sgs
delete_vpc "$vpc_id"