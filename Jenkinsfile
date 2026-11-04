// Pipeline declarativo: roda os mesmos passos do GitHub Actions dentro de containers.
pipeline {
  agent any

  environment {
    MIX_ENV = 'test'
    DB_CONTAINER = "ledger-pg-${env.BUILD_NUMBER}"
    MQ_CONTAINER = "ledger-mq-${env.BUILD_NUMBER}"
  }

  options {
    timeout(time: 20, unit: 'MINUTES')
    timestamps()
  }

  stages {
    stage('Postgres e RabbitMQ') {
      steps {
        sh 'docker run -d --name $DB_CONTAINER -e POSTGRES_PASSWORD=postgres postgres:16-alpine'
        sh 'docker run -d --name $MQ_CONTAINER rabbitmq:4.1-management-alpine'
        sh 'until docker exec $DB_CONTAINER pg_isready -U postgres; do sleep 1; done'
        sh 'until docker exec $MQ_CONTAINER rabbitmq-diagnostics -q ping; do sleep 2; done'
      }
    }

    stage('Build & Test') {
      agent {
        docker {
          image 'hexpm/elixir:1.18.4-erlang-27.3.4-debian-bookworm-20260610-slim'
          args "--link ${env.DB_CONTAINER}:db --link ${env.MQ_CONTAINER}:mq " +
               "-e DB_HOST=db -e RABBITMQ_URL=amqp://guest:guest@mq:5672"
          reuseNode true
        }
      }
      stages {
        stage('Deps') {
          steps {
            sh 'apt-get update -y && apt-get install -y build-essential git'
            sh 'mix local.hex --force && mix local.rebar --force && mix deps.get'
          }
        }
        stage('Lint') {
          steps {
            sh 'mix format --check-formatted'
            sh 'mix compile --warnings-as-errors'
            sh 'mix credo --strict'
          }
        }
        stage('Test') {
          steps { sh 'mix test --cover' }
        }
      }
    }

    stage('Docker image') {
      when { branch 'main' }
      steps { sh 'docker build -t ledger-umbrella:${GIT_COMMIT} .' }
    }
  }

  post {
    always { sh 'docker rm -f $DB_CONTAINER $MQ_CONTAINER || true' }
  }
}
