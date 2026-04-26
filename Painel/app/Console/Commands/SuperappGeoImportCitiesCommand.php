<?php

namespace App\Console\Commands;

use App\Console\Commands\Concerns\SuperappTracksJobs;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;

class SuperappGeoImportCitiesCommand extends Command
{
    use SuperappTracksJobs;

    protected $signature = 'superapp:geo-import-cities {--source=ibge} {--state=all} {--dry-run}';
    protected $description = 'Importa municípios do IBGE para br_cities';

    public function handle(): int
    {
        $source = strtolower((string)$this->option('source'));
        $state = strtoupper((string)$this->option('state'));
        $dryRun = (bool)$this->option('dry-run');

        if ($source !== 'ibge') {
            $this->error('Only --source=ibge is supported.');
            return self::FAILURE;
        }

        $this->startSuperappJob($this->getName(), $source, $this->options(), $dryRun);
        $ufs = $state === 'ALL'
            ? DB::table('br_states')->select('id', 'uf_code', 'ibge_code')->get()
            : DB::table('br_states')->where('uf_code', $state)->select('id', 'uf_code', 'ibge_code')->get();

        foreach ($ufs as $uf) {
            $cities = Http::timeout(120)->get("https://servicodados.ibge.gov.br/api/v1/localidades/estados/{$uf->uf_code}/municipios")->json();
            foreach ((array)$cities as $city) {
                $this->jobStats['processed_rows']++;
                $exists = DB::table('br_cities')->where('ibge_code', (int)$city['id'])->exists();

                if ($dryRun) {
                    $this->jobStats[$exists ? 'updated_rows' : 'inserted_rows']++;
                    continue;
                }

                DB::table('br_cities')->updateOrInsert(
                    ['ibge_code' => (int)$city['id']],
                    [
                        'state_id' => $uf->id,
                        'name' => $city['nome'],
                        'slug' => Str::slug($city['nome']),
                        'updated_at' => now(),
                        'created_at' => now(),
                    ]
                );
                $this->jobStats[$exists ? 'updated_rows' : 'inserted_rows']++;
            }
        }

        $manifest = $this->createManifest($this->getName(), ['stats' => $this->jobStats, 'source' => $source, 'state' => $state, 'dry_run' => $dryRun]);
        $this->finishSuperappJob($this->jobStats['error_rows'] ? 'completed_with_errors' : 'completed', $manifest, 'City import done');
        $this->info('Municípios processados: '.$this->jobStats['processed_rows']);

        return self::SUCCESS;
    }
}
