# =============================================================================
# Imagem custom do LocalStack para K8s (sem hostPath / sem socket do Docker).
# Build: bash infrastructure/localstack/build-lambda.sh
#        docker build -t fcg-localstack:local infrastructure/localstack/
# =============================================================================
FROM localstack/localstack:3.8

COPY init-aws.sh           /etc/localstack/init/ready.d/init-aws.sh
COPY .build/notifications-lambda.zip /opt/code/lambda/notifications-lambda.zip

RUN chmod +x /etc/localstack/init/ready.d/init-aws.sh
