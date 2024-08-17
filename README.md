### **Introduction**

The Amazon ECS (Elastic Container Service) Deployment Circuit Breaker stands out as a robust feature aimed at elevating the reliability and resilience of your application deployments. While updating applications is vital for maintaining a dynamic and evolving system, it introduces challenges that can potentially impact the user experience.

Acting as a safeguard during the deployment process, the ECS Deployment Circuit Breaker provides an automated and intelligent mechanism to identify and respond to issues associated with a new application version. This guide is designed to guide you through essential concepts, configuration steps, and best practices for effectively utilising the deployment circuit breaker in your ECS environment.

### **Why we need ECS Deployment Circuit Breaker ?**

consider below points about why we should enable circuit breaker in AWS ecs.

1. **Rollback Mechanism:**
    - In the event of a deployment failure, the circuit breaker can automatically trigger a rollback to the previously deployed task revision. This helps in quickly reverting to a stable state without manual intervention.
2. **Minimize Downtime:**
    - By preventing the deployment of a new task revision that is likely to fail, the circuit breaker reduces the risk of introducing service disruptions or downtime during deployments.
3. **Safety During Updates:**
    - During a deployment, the circuit breaker monitors the health of the new task revision. If it detects an unhealthy state or a specified error rate is exceeded, it prevents further deployment, ensuring that users are not impacted by potentially faulty changes.
4. **Automated Recovery:**
    - The circuit breaker automates the recovery process by rolling back to a known good state. This is crucial for maintaining service availability and reducing the need for manual intervention in the face of deployment issues.
5. **Improved Reliability:**
    - By incorporating deployment circuit breaker mechanisms, ECS promotes the reliability and stability of applications. It prevents the spread of faulty revisions, reducing the likelihood of widespread outages due to deployment errors.
6. **Configuration Flexibility:**
    - The ECS Deployment Circuit Breaker provides flexibility in its configuration, allowing users to set thresholds and conditions for triggering a rollback. This adaptability ensures that the circuit breaker aligns with the specific needs and characteristics of different applications.

### Deployment circuit breaker mechanism :

When the deployment circuit breaker determines that a deployment failed, it looks for the most recent deployment that is in a `COMPLETED` state. This is the deployment that it uses as the roll-back deployment. When the rollback starts, the deployment changes from a `COMPLETED` to `IN_PROGRESS`. This means that the deployment is not eligible for another rollback until it reaches the a `COMPLETED` state. When the deployment circuit breaker does not find a deployment that is in a `COMPLETED` state, the circuit breaker does not launch new tasks and the deployment is stalled.

When you create a service, the scheduler keeps track of the tasks that failed to launch in two stages.

- Stage 1 - The scheduler monitors the tasks to see if they transition into the RUNNING state.
    - Success - The deployment has a chance of transitioning to the COMPLETED state because there is more than one task that transitioned to the RUNNING state. The failure criteria is skipped and the circuit breaker moves to stage 2.
    - Failure - There are consecutive tasks that did not transition to the RUNNING state and the deployment might transition to the FAILED state.
- Stage 2 - The deployment enters this stage when there there is at least one task in the RUNNING state. The circuit breaker checks the health checks for the tasks in the current deployment being evaluated. The validated health checks are Elastic Load Balancing, AWS Cloud Map service health checks, and container health checks.
    - Success - There is at least one task in the running state with health checks that have passed.
    - Failure - The tasks that are replaced because of health check failures have reached the failure threshold.

### Failure threshold

The deployment circuit breaker calculates the threshold value, and then uses the value to determine when to move the deployment to a `FAILED` state.

The deployment circuit breaker has a minimum threshold of 3 and a maximum threshold of 200. and uses the values in the following formula to determine the deployment failure.

```
Minimum threshold <= 0.5 * desired task count => maximum threshold
```

When the result of the calculation is greater than the minimum of 3, but smaller than the maximum of 200, the failure threshold is set to the calculated threshold (rounded up).

## 2. Prerequisites

Before implementing the circuit breaker pattern, ensure the following prerequisites are met:

- A running ECS cluster
- Dockerized application with health checks
- AWS CLI installed and configured
- Basic understanding for Cloudformation and Serverless framework

The following table provides some examples.

| Desired task count | Calculation | Threshold |
| --- | --- | --- |
| 1 | 3 <= 0.5 * 1 => 200 | 3 (the calculated value is less than the minimum) |
| 25 | 3 <= 0.5 * 25 => 200 | 13 (the value is rounded up) |
| 400 | 3 <= 0.5 * 400 => 200 | 200 |
| 800 | 3 <= 0.5 * 800 => 200 | 200 (the calculated value is greater than the maximum) |

## 3. Setting up serverless configuration file with serverless-fargate plugin

```yaml
service: ecs-circuit-breaker

provider:
  name: aws
  runtime: nodejs18.x
  region: ap-south-1
  ecr:
    scanOnPush: true
    images:
      your_docker_image:
        path: .
  iamRoleStatements:
    - Effect: Allow
      Action:
        - ecr:DescribeRepositories
      Resource: '*'

fargate:
  clusterName: ecs-circuit-breaker-fargate
  containerInsights: true
  memory: '0.5GB'
  cpu: 256
  environment:
    name: test
  vpc:
    assignPublicIp: true
    securityGroupIds:
      - <group-id>
    subnetIds: 
      - <subnet-id-1>
      - <subnet-id-2>
  cloudFormationResource:
    service: # Here we need to define DeploymentCircuirBreaker Rule under Deployment Configuration
      DeploymentConfiguration:
        DeploymentCircuitBreaker:
          Enable: true
          Rollback: false
  tasks:
    ecs-circuit-breaker:
      name: circuit-breaker
      image: your_docker_image
      memory: '0.5GB'
      cpu: 256
      service:
        desiredCount: 1
        maximumPercent: 200 # default value
        minimumHealthyPercent: 100 # default value
      cloudFormationResource:
        container:
          PortMappings:
            - ContainerPort: 3000
              HostPort: 3000
      vpc:
        assignPublicIp: true
        securityGroupIds:
          - <group-id>
        subnetIds: 
          - <subnet-id-1>
          - <subnet-id-2>

plugins:
  - serverless-fargate
```

### 4. Basic server setup with Express

Here, we have defined just one test endpoint to test our deployment in ECS.

```jsx
const express = require('express')
const app = express()
const port = 3000

app.get('/', (req, res) => {
  res.send('Health Check!')
})

app.listen(port, () => {
  console.log(`App listening on port ${port}`)
})
```

### 5. Building a Docker image of Server

For now, we are going to use below commands to successfully build our docker image for deployment.

```jsx
FROM node:18-alpine
WORKDIR /src
COPY package*.json ./
RUN npm install
COPY . .
EXPOSE 3000
CMD [ "node", "server.js" ]
```

### 6. Test deployment rollback feature

Now our next step will be testing rollback feature of deployment circuit breaker.
In order to test it, we need to forcefully fail our deployment using below docker command.

```docker
FROM node:18-alpine
WORKDIR /src
COPY package*.json ./
RUN npm install
COPY . .
EXPOSE 3000
CMD [ "EXIT", "2" ]
```

In above Docker file, we have passed `exit 2` command to forcefully exit container without starting our server, which will end up as failed deployment.

Once you deploy above code, you will see one message in your cloudformation stack
`Error occurred during operation 'ECS Deployment Circuit Breaker was triggered.` 
which is showing that our deployment has failed and circuit breaker has triggered, so it will rollback to last successful deployment .