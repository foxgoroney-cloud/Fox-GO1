<?php

namespace App\Console\Commands;

use App\Console\Commands\Concerns\SuperappTracksJobs;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Schema;

class SuperappGeoImportStatesCommand extends Command
{
    use SuperappTracksJobs;

    protected $signature = 'superapp:geo-import-states {--source=ibge} {--dry-run}';
    protected $description = 'Importa UFs do Brasil de forma idempotente via IBGE';

    public function handle(): int
    {
        $source = strtolower((string)$this->option('source'));
        $dryRun = (bool)$this->option('dry-run');
        if ($source !== 'ibge') {
            $this->error('Only --source=ibge is supported.');
            return self::FAILURE;
        }

        $this->startSuperappJob($this->getName(), $source, $this->options(), $dryRun);
        $states = Http::timeout(60)->get('https://servicodados.ibge.gov.br/api/v1/localidades/estados')->json();

        foreach ((array)$states as $row) {
            $this->jobStats['processed_rows']++;
            if (!isset($row['id'], $row['sigla'], $row['nome'])) {
                $this->logImportError($this->jobStats['processed_rows'], null, 'Invalid IBGE payload', $row);
                continue;
            }

            $exists = Schema::hasTable('br_states')
                ? DB::table('br_states')->where('ibge_code', (int)$row['id'])->exists()
                : false;

            if ($dryRun || !Schema::hasTable('br_states')) {
                $this->jobStats[$exists ? 'updated_rows' : 'inserted_rows']++;
                continue;
            }

            DB::table('br_states')->updateOrInsert(
                ['ibge_code' => (int)$row['id']],
                [
                    'name' => $row['nome'],
                    'uf_code' => strtoupper($row['sigla']),
                    'region_name' => $row['regiao']['nome'] ?? null,
                    'region_ibge_code' => $row['regiao']['id'] ?? null,
                    'updated_at' => now(),
                    'created_at' => now(),
                ]
            );

            $this->jobStats[$exists ? 'updated_rows' : 'inserted_rows']++;
        }

        $manifest = $this->createManifest($this->getName(), ['stats' => $this->jobStats, 'source' => $source, 'dry_run' => $dryRun]);
        $this->finishSuperappJob($this->jobStats['error_rows'] ? 'completed_with_errors' : 'completed', $manifest, 'UF import done');
        $this->info('Estados processados: '.$this->jobStats['processed_rows']);

        return self::SUCCESS;
    }
}
