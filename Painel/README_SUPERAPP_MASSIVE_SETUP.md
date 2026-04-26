# Brasil Superapp Massive Setup (Fox GO / 6amMart)

## Pré-requisitos
1. Rodar migrations novas sem `database:refresh`:
   - `php artisan migrate`
2. Garantir CSVs grandes em:
   - `storage/imports/neighborhoods.csv`
   - `storage/imports/postal_codes.csv`
   - `storage/imports/skus.csv`

## Ordem exata (dry-run recomendado primeiro)
1. `php artisan superapp:geo-import-states --source=ibge --dry-run`
2. `php artisan superapp:geo-import-cities --source=ibge --state=all --dry-run`
3. `php artisan superapp:geo-import-neighborhoods --source=csv --file=storage/imports/neighborhoods.csv --dry-run`
4. `php artisan superapp:geo-import-postal-codes --source=csv --file=storage/imports/postal_codes.csv --dry-run`
5. `php artisan superapp:zone-build --strategy=city_cluster --target-active=25000 --target-surge=10000 --dry-run`
6. `php artisan superapp:zone-sync-modules --modules=all --dry-run`
7. `php artisan superapp:catalog-expand --module-types=food,grocery,pharmacy,ecommerce,parcel --dry-run`
8. `php artisan superapp:sku-import --source=csv --file=storage/imports/skus.csv --chunk=5000 --dry-run`
9. `php artisan superapp:audit-scale`
10. `php artisan superapp:export-all`
11. `php artisan superapp:launch-massive-setup --dry-run`

## Execução real
Após validar os manifests de dry-run (`storage/app/superapp/manifests`), repetir os comandos de import/build sem `--dry-run`.

## Garantias implementadas
- Idempotência por `updateOrInsert` e chaves únicas.
- Chunk/streaming para CSV grande sem carregar tudo na memória.
- Manifest por execução.
- Job log em `superapp_import_jobs`.
- Erro por linha em `superapp_import_errors`.
- Sem apagar dados existentes.
