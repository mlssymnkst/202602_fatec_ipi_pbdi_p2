# Prova - Data Warehouse com PostgreSQL

## Integrantes
- Mariana Meneses Borges da Costa - RA 2041382521002
- Melissa Yumi Nakasato - RA 2041382521003

## Ambiente AWS
- Integrante dono da conta: MELISSA YUMI NAKASATO
- RA usado nos nomes dos recursos: 2041382521003
- ID da conta AWS: 208806792083
- Região: us-east-1

## Dataset
- (a) Quantidade de linhas de dados, sem o cabeçalho: 9800
- (b) Formato das datas: dd/mm/aaaa (exemplo: 08/11/2017), nas duas colunas (Order Date e Ship Date). Justificativa: a linha de Row ID 13 tem Order Date 15/04/2018. Não existe mês 15, então o primeiro número só pode ser o dia e o segundo o mês.
- (c) Linhas sem código postal: 11
- (d) Nome de produto com vírgula: "Hon Deluxe Fabric Upholstered Stacking Chairs, Rounded Back" (Row ID 2). Essa vírgula não separa colunas porque o nome está entre aspas duplas no arquivo, e no formato CSV uma vírgula dentro de aspas faz parte do valor.
