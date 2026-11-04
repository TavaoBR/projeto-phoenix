// Pipeline declarativo: roda os mesmos passos do GitHub Actions dentro de containers.
pipeline {
  agent any

  environment {
    MIX_ENV = 'test'
    DB_CONTAINER = "ledger-pg-${env.BUILD_NUMBER}"
  }

  options {
    timeout(time: 20, unit: 'MINUTES')
    timestamps()
  }

  stages {
    stage('Postgres') {
      steps {
        sh 'docker run -d --name $DB_CONTAINER -e POSTGRES_PASSWORD=postgres postgres:16-alpine'
        sh 'until docker exec $DB_CONTAINER pg_isready -U postgres; do sleep 1; done'
      }
    }

    stage('Build & Test') {
      agent {
        docker {
          image 'hexpm/elixir:1.18.4-erlang-27.3.4-debian-bookworm-20260610-slim'
          args "--link ${env.DB_CONTAINER}:db -e DB_HOST=db"
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
    always { sh 'docker rm -f $DB_CONTAINER || true' }
  }
}
