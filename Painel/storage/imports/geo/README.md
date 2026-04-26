# GeoJSON de Zonas Brasil

Este diretório deve conter os arquivos GeoJSON usados pelo comando:

- `br_states.geojson`
- `br_cities.geojson`
- `br_neighborhoods.geojson`

## Regras mínimas de propriedades

### Estados (`br_states.geojson`)
Cada `feature.properties` deve incluir ao menos uma chave de código IBGE do estado:
- `ibge_code` **ou** `codigo_ibge` **ou** `codigo` **ou** `id`

### Cidades (`br_cities.geojson`)
Cada `feature.properties` deve incluir ao menos uma chave de código IBGE da cidade:
- `ibge_code` **ou** `codigo_ibge` **ou** `codigo_municipio` **ou** `id`

### Bairros (`br_neighborhoods.geojson`)
Cada `feature.properties` deve incluir:
- código IBGE da cidade: `city_ibge_code` **ou** `codigo_ibge_cidade` **ou** `ibge_city_code` **ou** `municipio_ibge`
- nome do bairro: `name` **ou** `bairro` **ou** `nome`

Geometrias aceitas: `Polygon` e `MultiPolygon`.

## Comando único (one-shot)

Depois de colocar os arquivos/CSVs, rode:

```bash
php artisan superapp:zones-one-shot-br --state=all --modules=all --provider=geojson
```

Opções úteis:
- `--skip-neighborhoods` (não cria zonas de bairro)
- `--skip-postal-codes` (não importa faixas de CEP)
- `--dry-run` (simulação)
