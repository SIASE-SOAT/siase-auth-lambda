# ADR-002 — Escolha da AWS como Provedor de Nuvem

**Status:** Aceito
**Data:** 2026
**Repositorio:** siase-auth-lambda

## Contexto

O sistema SIASE precisa de uma infraestrutura de nuvem para hospedar a aplicacao, o banco de dados, as funcoes serverless e o API Gateway. A escolha do provedor impacta custo, disponibilidade de servicos, integracao entre componentes e curva de aprendizado da equipe.

## Decisao

Adotar a **AWS (Amazon Web Services)** como provedor de nuvem unico para todos os componentes do SIASE.

## Justificativa

- **Ecossistema integrado:** EKS, RDS, Lambda, API Gateway, Secrets Manager, SSM Parameter Store e CloudWatch sao servicos nativos que se integram via IAM sem necessidade de configuracao adicional de rede ou autenticacao entre servicos.
- **AWS Academy Learner Lab:** o ambiente academico disponibiliza credenciais temporarias e uma `LabRole` pre-configurada, viabilizando o provisionamento sem necessidade de criar roles IAM do zero.
- **Terraform AWS Provider:** provider oficial maduro com suporte a todos os servicos utilizados.
- **Disponibilidade regional:** `us-east-1` oferece o maior numero de servicos e AZs disponíveis, reduzindo risco de indisponibilidade de servico especifico.
- **Mercado:** AWS e o provedor com maior market share em cloud, relevante para o contexto academico e profissional.

## Alternativas Consideradas

| Alternativa | Motivo da Rejeicao                                                              |
|-------------|---------------------------------------------------------------------------------|
| GCP         | Menor familiaridade da equipe; Learner Lab nao disponivel para GCP              |
| Azure       | Idem GCP; integracao com GitHub Actions via OIDC e menos madura que AWS        |
| Multi-cloud | Complexidade operacional desproporcional ao escopo do projeto                   |

## Consequencias

- Todos os recursos sao provisionados na regiao `us-east-1` por padrao.
- O estado Terraform e armazenado em S3 com lock via DynamoDB.
- A autenticacao do CI/CD com a AWS e feita exclusivamente via OIDC — nenhuma chave de acesso estatica e armazenada em repositorios ou GitHub Secrets.
- O custo e otimizado para o Learner Lab: instancias `t3.micro`/`t3.medium`, sem NAT Gateway, sem Multi-AZ no RDS por padrao.
