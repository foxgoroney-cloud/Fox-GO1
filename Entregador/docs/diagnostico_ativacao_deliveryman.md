# Diagnostico: bloqueio de login do app do entregador

## Evidencia coletada

- O app envia login para `POST /api/v1/auth/delivery-man/login` (`AppConstants.loginUri`).
- Quando o backend retorna erro, o app exibe `response.statusText` (campo `message` vindo da API).
- O bloqueio analisado nao e criado pelo Flutter. Ele vem do backend na autenticacao.

## Origem real do erro

A mensagem de bloqueio observada e retornada pelo backend/admin durante a rota de login do app do entregador.

Esse tipo de validacao costuma ficar no fluxo de ativacao ou licenca do modulo do app de entregador. Sem essa ativacao, o login pode responder com erro mesmo quando o app mobile esta configurado corretamente.

## Onde validar no Admin

No painel administrativo da plataforma:

1. Acesse a area de configuracao de licenca, addons ou modulos.
2. Localize o modulo do app de entregador.
3. Confirme se a ativacao ou licenca foi aplicada corretamente.
4. Salve, limpe cache ou configuracao quando necessario e teste novamente o endpoint de login.

## Arquivos mapeados neste repositorio

- Endpoint de login: `lib/util/app_constants.dart`
- Chamada HTTP do login: `lib/features/auth/domain/repositories/auth_repository.dart`
- Propagacao do erro para UI: `lib/features/auth/controllers/auth_controller.dart`
- Conversao do `message` JSON em `statusText`: `lib/api/api_client.dart`

## Observacao

Este repositorio contem somente o app Flutter do entregador. As validacoes de backend que bloqueiam login nao estao implementadas aqui.
