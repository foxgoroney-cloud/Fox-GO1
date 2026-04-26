<?php

namespace App\Console\Commands;

use App\Models\Module;
use App\Models\Zone;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;
use MatanYadaev\EloquentSpatial\Objects\LineString;
use MatanYadaev\EloquentSpatial\Objects\Point;
use MatanYadaev\EloquentSpatial\Objects\Polygon;

class SuperappZoneImportBrazilCommand extends Command
{
    protected $signature = 'superapp:zone-import-brazil
                            {--level=all : all|state|city|neighborhood}
                            {--state=all : UF filter (ex: SP)}
                            {--city= : city IBGE code filter}
                            {--limit=0 : max rows per level (0 = no limit)}
                            {--modules=all : module IDs csv or "all"}
                            {--provider=geojson : geojson|nominatim}
                            {--states-geojson=storage/imports/geo/br_states.geojson : GeoJSON file for states}
                            {--cities-geojson=storage/imports/geo/br_cities.geojson : GeoJSON file for cities}
                            {--neighborhoods-geojson=storage/imports/geo/br_neighborhoods.geojson : GeoJSON file for neighborhoods}
                            {--sleep-ms=1200 : pause between calls (nominatim)}
                            {--retries=3 : retries per lookup (nominatim)}
                            {--fail-on-error=1 : 1=abort with failure when any row errors}
                            {--dry-run}';

    protected $description = 'Cria/atualiza zonas reais do Brasil com dados geográficos oficiais (preferência GeoJSON local)';

    private array $geojsonCache = [];

    private const CAPITALS_BY_UF = [
        'AC' => 'Rio Branco', 'AL' => 'Maceió', 'AP' => 'Macapá', 'AM' => 'Manaus', 'BA' => 'Salvador',
        'CE' => 'Fortaleza', 'DF' => 'Brasília', 'ES' => 'Vitória', 'GO' => 'Goiânia', 'MA' => 'São Luís',
        'MT' => 'Cuiabá', 'MS' => 'Campo Grande', 'MG' => 'Belo Horizonte', 'PA' => 'Belém', 'PB' => 'João Pessoa',
        'PR' => 'Curitiba', 'PE' => 'Recife', 'PI' => 'Teresina', 'RJ' => 'Rio de Janeiro', 'RN' => 'Natal',
        'RS' => 'Porto Alegre', 'RO' => 'Porto Velho', 'RR' => 'Boa Vista', 'SC' => 'Florianópolis',
        'SP' => 'São Paulo', 'SE' => 'Aracaju', 'TO' => 'Palmas',
    ];

    public function handle(): int
    {
        $levelOption = strtolower((string)$this->option('level'));
        $levels = match ($levelOption) {
            'all' => ['state', 'city', 'neighborhood'],
            'state', 'city', 'neighborhood' => [$levelOption],
            default => null,
        };

        if ($levels === null) {
            $this->error('Invalid --level. Use: all, state, city or neighborhood.');
            return self::FAILURE;
        }

        $provider = strtolower((string)$this->option('provider'));
        if (!in_array($provider, ['geojson', 'nominatim'], true)) {
            $this->error('Invalid --provider. Use: geojson or nominatim.');
            return self::FAILURE;
        }

        $dryRun = (bool)$this->option('dry-run');
        $limit = max(0, (int)$this->option('limit'));
        $sleepMs = max(0, (int)$this->option('sleep-ms'));
        $retries = max(1, (int)$this->option('retries'));
        $failOnError = (int)$this->option('fail-on-error') === 1;

        $moduleIds = $this->resolveModules((string)$this->option('modules'));
        if ($moduleIds === false) {
            return self::FAILURE;
        }

        if (!Schema::hasTable('zones')) {
            $this->error('zones table not found.');
            return self::FAILURE;
        }

        if ($provider === 'geojson') {
            foreach ($levels as $level) {
                if (!$this->loadGeoJsonForLevel($level)) {
                    return self::FAILURE;
                }
            }
        }

        $summary = ['processed' => 0, 'inserted' => 0, 'updated' => 0, 'errors' => 0];

        foreach ($levels as $level) {
            $result = $this->processLevel($level, $provider, $moduleIds, $dryRun, $limit, $sleepMs, $retries);
            $summary['processed'] += $result['processed'];
            $summary['inserted'] += $result['inserted'];
            $summary['updated'] += $result['updated'];
            $summary['errors'] += $result['errors'];
        }

        $this->info("Finalizado. processados={$summary['processed']} inseridos={$summary['inserted']} atualizados={$summary['updated']} erros={$summary['errors']}");

        if ($summary['errors'] > 0 && $failOnError) {
            return self::FAILURE;
        }

        return self::SUCCESS;
    }

    private function processLevel(string $level, string $provider, array $moduleIds, bool $dryRun, int $limit, int $sleepMs, int $retries): array
    {
        $rows = $this->getGeoRows($level);
        if ($rows->isEmpty()) {
            $this->warn("Nível {$level}: nenhum registro encontrado.");
            return ['processed' => 0, 'inserted' => 0, 'updated' => 0, 'errors' => 0];
        }

        $processed = 0;
        $inserted = 0;
        $updated = 0;
        $errors = 0;

        foreach ($rows as $row) {
            if ($limit > 0 && $processed >= $limit) {
                break;
            }

            $processed++;
            $ring = $provider === 'geojson'
                ? $this->findRingFromGeoJsonIndex($level, $row)
                : $this->fetchBoundaryRingFromNominatim($this->buildSearchQuery($level, $row), $retries);

            if (!$ring) {
                $errors++;
                $this->warn("[{$level}][{$processed}] sem polígono para registro {$this->rowIdentifier($level, $row)}");
                continue;
            }

            [$zoneName, $displayName] = $this->buildZoneNames($level, $row);
            $existingZone = Zone::withoutGlobalScopes()->where('name', $zoneName)->first();

            if (!$dryRun) {
                $zone = $existingZone ?: new Zone();

                if (!$existingZone) {
                    $nextZoneId = ((int)(Zone::withoutGlobalScopes()->max('id'))) + 1;
                    $zone->store_wise_topic = 'zone_'.$nextZoneId.'_store';
                    $zone->customer_wise_topic = 'zone_'.$nextZoneId.'_customer';
                    $zone->deliveryman_wise_topic = 'zone_'.$nextZoneId.'_delivery_man';
                    if (Schema::hasColumn('zones', 'rider_wise_topic')) {
                        $zone->rider_wise_topic = 'zone_'.$nextZoneId.'_rider';
                    }
                }

                $zone->name = $zoneName;
                if (Schema::hasColumn('zones', 'display_name')) {
                    $zone->display_name = $displayName;
                }
                $zone->coordinates = $this->buildPolygon($ring);
                $zone->status = 1;
                $zone->cash_on_delivery = 1;
                $zone->digital_payment = 1;
                if (Schema::hasColumn('zones', 'offline_payment')) {
                    $zone->offline_payment = 1;
                }
                $zone->save();

                if (!empty($moduleIds)) {
                    $zone->modules()->syncWithoutDetaching($moduleIds);
                }
            }

            if ($existingZone) {
                $updated++;
            } else {
                $inserted++;
            }

            $this->line("[{$level}][{$processed}] ok: {$displayName}");
            if ($provider === 'nominatim' && $sleepMs > 0) {
                usleep($sleepMs * 1000);
            }
        }

        $this->info("Nível {$level}: processados={$processed} inseridos={$inserted} atualizados={$updated} erros={$errors}");

        return compact('processed', 'inserted', 'updated', 'errors');
    }

    private function rowIdentifier(string $level, object $row): string
    {
        return match ($level) {
            'state' => (string)($row->ibge_code ?? $row->uf_code ?? 'unknown-state'),
            'city' => (string)($row->ibge_code ?? 'unknown-city'),
            default => (string)($row->city_ibge_code ?? 'unknown-neighborhood').':'.Str::slug((string)($row->neighborhood_name ?? '')),
        };
    }

    private function loadGeoJsonForLevel(string $level): bool
    {
        $path = match ($level) {
            'state' => (string)$this->option('states-geojson'),
            'city' => (string)$this->option('cities-geojson'),
            default => (string)$this->option('neighborhoods-geojson'),
        };

        $absolutePath = base_path($path);
        if (!is_file($absolutePath)) {
            $this->error("GeoJSON not found for {$level}: {$absolutePath}");
            return false;
        }

        $json = json_decode((string)file_get_contents($absolutePath), true);
        if (!is_array($json) || !isset($json['features']) || !is_array($json['features'])) {
            $this->error("Invalid GeoJSON for {$level}: {$absolutePath}");
            return false;
        }

        $index = [];
        foreach ($json['features'] as $feature) {
            $properties = (array)($feature['properties'] ?? []);
            $geometry = (array)($feature['geometry'] ?? []);
            $ring = $this->extractRingFromGeometry($geometry);
            if (!$ring) {
                continue;
            }

            if ($level === 'state') {
                $key = $this->normalizeDigits((string)$this->firstFilled($properties, ['ibge_code', 'codigo_ibge', 'codigo', 'id']));
                if ($key !== '') {
                    $index[$key] = $ring;
                }
                continue;
            }

            if ($level === 'city') {
                $key = $this->normalizeDigits((string)$this->firstFilled($properties, ['ibge_code', 'codigo_ibge', 'codigo_municipio', 'id']));
                if ($key !== '') {
                    $index[$key] = $ring;
                }
                continue;
            }

            $cityIbge = $this->normalizeDigits((string)$this->firstFilled($properties, ['city_ibge_code', 'codigo_ibge_cidade', 'ibge_city_code', 'municipio_ibge']));
            $name = Str::slug((string)$this->firstFilled($properties, ['name', 'bairro', 'nome']));
            if ($cityIbge !== '' && $name !== '') {
                $index[$cityIbge.'|'.$name] = $ring;
            }
        }

        if (empty($index)) {
            $this->error("No usable features indexed for {$level} from {$absolutePath}");
            return false;
        }

        $this->geojsonCache[$level] = $index;
        $this->info("GeoJSON {$level} indexado: ".count($index).' registros úteis');

        return true;
    }

    private function firstFilled(array $properties, array $keys): mixed
    {
        foreach ($keys as $key) {
            if (array_key_exists($key, $properties) && $properties[$key] !== null && $properties[$key] !== '') {
                return $properties[$key];
            }
        }

        return null;
    }

    private function findRingFromGeoJsonIndex(string $level, object $row): ?array
    {
        $index = $this->geojsonCache[$level] ?? [];
        if (empty($index)) {
            return null;
        }

        if ($level === 'state') {
            $key = $this->normalizeDigits((string)$row->ibge_code);
            return $index[$key] ?? null;
        }

        if ($level === 'city') {
            $key = $this->normalizeDigits((string)$row->ibge_code);
            return $index[$key] ?? null;
        }

        $key = $this->normalizeDigits((string)$row->city_ibge_code).'|'.Str::slug((string)$row->neighborhood_name);
        return $index[$key] ?? null;
    }

    private function normalizeDigits(string $value): string
    {
        return preg_replace('/\D+/', '', $value) ?? '';
    }

    private function extractRingFromGeometry(array $geometry): ?array
    {
        $type = (string)($geometry['type'] ?? '');
        $coords = $geometry['coordinates'] ?? null;
        if (!is_array($coords)) {
            return null;
        }

        $ringLngLat = null;
        if ($type === 'Polygon') {
            $ringLngLat = $coords[0] ?? null;
        } elseif ($type === 'MultiPolygon') {
            $bestArea = null;
            foreach ($coords as $polygon) {
                $candidate = $polygon[0] ?? null;
                if (!is_array($candidate)) {
                    continue;
                }

                $area = $this->ringArea($candidate);
                if ($bestArea === null || $area > $bestArea) {
                    $bestArea = $area;
                    $ringLngLat = $candidate;
                }
            }
        }

        if (!is_array($ringLngLat) || count($ringLngLat) < 4) {
            return null;
        }

        $ringLatLng = [];
        foreach ($ringLngLat as $point) {
            if (!is_array($point) || !isset($point[0], $point[1])) {
                continue;
            }
            $ringLatLng[] = [(float)$point[1], (float)$point[0]];
        }

        if (count($ringLatLng) < 4) {
            return null;
        }

        $first = $ringLatLng[0];
        $last = $ringLatLng[count($ringLatLng) - 1];
        if ((float)$first[0] !== (float)$last[0] || (float)$first[1] !== (float)$last[1]) {
            $ringLatLng[] = $first;
        }

        return $ringLatLng;
    }

    private function getGeoRows(string $level)
    {
        $state = strtoupper((string)$this->option('state'));
        $cityIbgeCode = trim((string)$this->option('city'));

        if ($level === 'state') {
            $query = DB::table('br_states')->select('id', 'name', 'uf_code', 'ibge_code')->orderBy('uf_code');
            if ($state !== '' && $state !== 'ALL') {
                $query->where('uf_code', $state);
            }
            return $query->get();
        }

        if ($level === 'city') {
            $query = DB::table('br_cities as c')
                ->join('br_states as s', 's.id', '=', 'c.state_id')
                ->select('c.id', 'c.ibge_code', 'c.name', 's.uf_code')
                ->orderBy('s.uf_code')
                ->orderBy('c.name');

            if ($state !== '' && $state !== 'ALL') {
                $query->where('s.uf_code', $state);
            }

            if ($cityIbgeCode !== '') {
                $query->where('c.ibge_code', (int)$cityIbgeCode);
            }

            return $query->get();
        }

        $query = DB::table('br_neighborhoods as n')
            ->join('br_cities as c', 'c.id', '=', 'n.city_id')
            ->join('br_states as s', 's.id', '=', 'c.state_id')
            ->select('n.id', 'n.name as neighborhood_name', 'c.name as city_name', 'c.ibge_code as city_ibge_code', 's.uf_code')
            ->orderBy('s.uf_code')
            ->orderBy('c.name')
            ->orderBy('n.name');

        if ($state !== '' && $state !== 'ALL') {
            $query->where('s.uf_code', $state);
        }

        if ($cityIbgeCode !== '') {
            $query->where('c.ibge_code', (int)$cityIbgeCode);
        }

        return $query->get();
    }

    private function buildSearchQuery(string $level, object $row): string
    {
        return match ($level) {
            'state' => sprintf('%s, Brasil', $row->name),
            'city' => sprintf('%s, %s, Brasil', $row->name, $row->uf_code),
            default => sprintf('%s, %s, %s, Brasil', $row->neighborhood_name, $row->city_name, $row->uf_code),
        };
    }

    private function buildZoneNames(string $level, object $row): array
    {
        if ($level === 'state') {
            return [
                sprintf('BR|ESTADO|%s', strtoupper($row->uf_code)),
                sprintf('%s (%s)', $row->name, strtoupper($row->uf_code)),
            ];
        }

        if ($level === 'city') {
            $isCapital = isset(self::CAPITALS_BY_UF[$row->uf_code])
                && Str::lower((string)self::CAPITALS_BY_UF[$row->uf_code]) === Str::lower((string)$row->name);

            return [
                sprintf('BR|CIDADE|%s', (string)$row->ibge_code),
                $isCapital
                    ? sprintf('%s Capital/%s', $row->name, strtoupper($row->uf_code))
                    : sprintf('%s/%s', $row->name, strtoupper($row->uf_code)),
            ];
        }

        return [
            sprintf('BR|BAIRRO|%s|%s', (string)$row->city_ibge_code, Str::slug((string)$row->neighborhood_name)),
            sprintf('%s - %s/%s', $row->neighborhood_name, $row->city_name, strtoupper($row->uf_code)),
        ];
    }

    private function fetchBoundaryRingFromNominatim(string $query, int $retries): ?array
    {
        for ($attempt = 1; $attempt <= $retries; $attempt++) {
            $response = Http::timeout(45)
                ->withHeaders([
                    'User-Agent' => 'FoxGo Zone Importer/1.0',
                    'Accept-Language' => 'pt-BR',
                ])
                ->get('https://nominatim.openstreetmap.org/search', [
                    'q' => $query,
                    'format' => 'jsonv2',
                    'limit' => 1,
                    'polygon_geojson' => 1,
                    'countrycodes' => 'br',
                ]);

            if ($response->successful()) {
                $geoJson = data_get($response->json(), '0.geojson');
                if (is_array($geoJson)) {
                    $ring = $this->extractRingFromGeometry($geoJson);
                    if ($ring) {
                        return $ring;
                    }
                }
            }

            if ($attempt < $retries) {
                usleep(300000 * $attempt);
            }
        }

        return null;
    }

    private function ringArea(array $ring): float
    {
        $sum = 0.0;
        $count = count($ring);
        if ($count < 4) {
            return 0.0;
        }

        for ($i = 0; $i < $count - 1; $i++) {
            $x1 = (float)($ring[$i][0] ?? 0);
            $y1 = (float)($ring[$i][1] ?? 0);
            $x2 = (float)($ring[$i + 1][0] ?? 0);
            $y2 = (float)($ring[$i + 1][1] ?? 0);
            $sum += ($x1 * $y2) - ($x2 * $y1);
        }

        return abs($sum / 2);
    }

    private function buildPolygon(array $ring): Polygon
    {
        $points = [];
        foreach ($ring as $point) {
            $points[] = new Point((float)$point[0], (float)$point[1]);
        }

        return new Polygon([new LineString($points)]);
    }

    private function resolveModules(string $moduleInput): array|bool
    {
        $moduleInput = trim($moduleInput);
        if ($moduleInput === '' || strtolower($moduleInput) === 'all') {
            return Module::withoutGlobalScopes()->pluck('id')->all();
        }

        $ids = array_values(array_unique(array_filter(array_map('trim', explode(',', $moduleInput)), fn ($value) => $value !== '')));
        foreach ($ids as $id) {
            if (!ctype_digit($id)) {
                $this->error("Invalid module id '{$id}'. Use comma-separated integer IDs or --modules=all.");
                return false;
            }
        }

        $ids = array_map('intval', $ids);
        $validIds = Module::withoutGlobalScopes()->whereIn('id', $ids)->pluck('id')->all();
        if (count($ids) !== count($validIds)) {
            $invalid = implode(',', array_diff($ids, $validIds));
            $this->error("Invalid module IDs: {$invalid}");
            return false;
        }

        return $ids;
    }
}
