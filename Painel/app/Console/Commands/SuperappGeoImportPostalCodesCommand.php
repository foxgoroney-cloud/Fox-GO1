<?php

namespace App\Console\Commands;

use App\Console\Commands\Concerns\SuperappTracksJobs;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

class SuperappGeoImportPostalCodesCommand extends Command
{
    use SuperappTracksJobs;

    protected $signature = 'superapp:geo-import-postal-codes {--source=csv} {--file=storage/imports/postal_codes.csv} {--chunk=5000} {--dry-run}';
    protected $description = 'Importa faixas de CEP em streaming via CSV';

    public function handle(): int
    {
        $dryRun = (bool)$this->option('dry-run');
        $file = base_path((string)$this->option('file'));
        $chunk = max(500, (int)$this->option('chunk'));
        $this->startSuperappJob($this->getName(), 'csv', $this->options(), $dryRun);

        if (!is_file($file)) {
            $this->error("CSV not found: {$file}");
            return self::FAILURE;
        }

        $csv = new \SplFileObject($file);
        $csv->setFlags(\SplFileObject::READ_CSV | \SplFileObject::SKIP_EMPTY);
        $headers = null;

        foreach ($csv as $index => $line) {
            if ($index === 0) {
                $headers = array_map('trim', (array)$line);
                continue;
            }
            if (!$headers || $line === [null]) {
                continue;
            }

            $row = array_combine($headers, array_pad((array)$line, count($headers), null));
            $this->jobStats['processed_rows']++;

            $cepStart = preg_replace('/\D+/', '', (string)($row['cep_start'] ?? ''));
            $cepEnd = preg_replace('/\D+/', '', (string)($row['cep_end'] ?? ''));
            if (strlen($cepStart) !== 8 || strlen($cepEnd) !== 8 || $cepStart > $cepEnd) {
                $this->logImportError($index + 1, null, 'Invalid CEP range', $row);
                continue;
            }

            $city = isset($row['city_ibge_code']) ? DB::table('br_cities')->where('ibge_code', (int)$row['city_ibge_code'])->first() : null;
            $stateId = $city?->state_id;
            if (!$stateId && !empty($row['state_uf'])) {
                $stateId = DB::table('br_states')->where('uf_code', strtoupper((string)$row['state_uf']))->value('id');
            }

            $neighborhoodId = null;
            if (!empty($row['neighborhood_name']) && $city) {
                $norm = mb_strtolower(trim(preg_replace('/\s+/', ' ', (string)$row['neighborhood_name'])));
                $neighborhoodId = DB::table('br_neighborhoods')->where('city_id', $city->id)->where('name_normalized', $norm)->value('id');
            }

            $rangeKey = sha1(implode('|', [$cepStart, $cepEnd, $city->id ?? 0, $neighborhoodId ?? 0]));
            $exists = DB::table('postal_code_ranges')->where('range_key', $rangeKey)->exists();

            if (!$dryRun) {
                DB::table('postal_code_ranges')->updateOrInsert(
                    ['range_key' => $rangeKey],
                    [
                        'state_id' => $stateId,
                        'city_id' => $city->id ?? null,
                        'neighborhood_id' => $neighborhoodId,
                        'cep_start' => $cepStart,
                        'cep_end' => $cepEnd,
                        'updated_at' => now(),
                        'created_at' => now(),
                    ]
                );
            }

            $this->jobStats[$exists ? 'updated_rows' : 'inserted_rows']++;
            if (($this->jobStats['processed_rows'] % $chunk) === 0) {
                $this->line("Processed {$this->jobStats['processed_rows']} rows...");
            }
        }

        $manifest = $this->createManifest($this->getName(), ['stats' => $this->jobStats, 'file' => $file, 'dry_run' => $dryRun]);
        $this->finishSuperappJob($this->jobStats['error_rows'] ? 'completed_with_errors' : 'completed', $manifest, 'Postal import done');

        return self::SUCCESS;
    }
}
