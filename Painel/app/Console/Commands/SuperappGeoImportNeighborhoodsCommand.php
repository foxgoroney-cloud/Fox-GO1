<?php

namespace App\Console\Commands;

use App\Console\Commands\Concerns\SuperappTracksJobs;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

class SuperappGeoImportNeighborhoodsCommand extends Command
{
    use SuperappTracksJobs;

    protected $signature = 'superapp:geo-import-neighborhoods {--source=csv} {--file=storage/imports/neighborhoods.csv} {--chunk=5000} {--dry-run}';
    protected $description = 'Importa bairros/localidades via CSV em streaming';

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
            if (!$headers || $line === [null] || count(array_filter((array)$line, fn ($v) => $v !== null && $v !== '')) === 0) {
                continue;
            }

            $row = array_combine($headers, array_pad((array)$line, count($headers), null));
            $this->jobStats['processed_rows']++;

            $cityIbge = preg_replace('/\D+/', '', (string)($row['city_ibge_code'] ?? ''));
            $name = trim((string)($row['name'] ?? ''));
            if ($cityIbge === '' || $name === '') {
                $this->logImportError($index + 1, null, 'Missing city_ibge_code or name', $row);
                continue;
            }

            $city = DB::table('br_cities')->where('ibge_code', (int)$cityIbge)->first();
            if (!$city) {
                $this->logImportError($index + 1, $cityIbge, 'City not found', $row);
                continue;
            }

            $normalized = mb_strtolower(trim(preg_replace('/\s+/', ' ', $name)));
            $exists = DB::table('br_neighborhoods')->where('city_id', $city->id)->where('name_normalized', $normalized)->exists();

            if (!$dryRun) {
                DB::table('br_neighborhoods')->updateOrInsert(
                    ['city_id' => $city->id, 'name_normalized' => $normalized],
                    [
                        'name' => $name,
                        'external_code' => $row['external_code'] ?? null,
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
        $this->finishSuperappJob($this->jobStats['error_rows'] ? 'completed_with_errors' : 'completed', $manifest, 'Neighborhood import done');

        return self::SUCCESS;
    }
}
