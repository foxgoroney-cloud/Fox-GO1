<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;
use Illuminate\Support\Facades\Artisan;

class SuperappZoneOneShotBrazilCommand extends Command
{
    protected $signature = 'superapp:zones-one-shot-br
                            {--state=all : UF filter}
                            {--modules=all : module IDs csv or all}
                            {--provider=geojson : geojson|nominatim}
                            {--states-geojson=storage/imports/geo/br_states.geojson}
                            {--cities-geojson=storage/imports/geo/br_cities.geojson}
                            {--neighborhoods-geojson=storage/imports/geo/br_neighborhoods.geojson}
                            {--neighborhoods-csv=storage/imports/neighborhoods.csv}
                            {--postal-codes-csv=storage/imports/postal_codes.csv}
                            {--skip-neighborhoods : skip neighborhood import/build}
                            {--skip-postal-codes : skip postal code import}
                            {--dry-run}';

    protected $description = 'Comando único para preparar geografia BR e criar zonas com vínculo de módulos';

    public function handle(): int
    {
        $dryRun = (bool)$this->option('dry-run');
        $state = (string)$this->option('state');
        $modules = (string)$this->option('modules');
        $provider = (string)$this->option('provider');

        $commands = [
            ['superapp:geo-import-states', ['--source' => 'ibge', '--dry-run' => $dryRun]],
            ['superapp:geo-import-cities', ['--source' => 'ibge', '--state' => $state, '--dry-run' => $dryRun]],
        ];

        if (!$this->option('skip-neighborhoods')) {
            $commands[] = [
                'superapp:geo-import-neighborhoods',
                ['--source' => 'csv', '--file' => (string)$this->option('neighborhoods-csv'), '--dry-run' => $dryRun],
            ];
        }

        if (!$this->option('skip-postal-codes')) {
            $commands[] = [
                'superapp:geo-import-postal-codes',
                ['--source' => 'csv', '--file' => (string)$this->option('postal-codes-csv'), '--dry-run' => $dryRun],
            ];
        }

        $zoneCommandArgs = [
            '--level' => $this->option('skip-neighborhoods') ? 'city' : 'all',
            '--state' => $state,
            '--modules' => $modules,
            '--provider' => $provider,
            '--states-geojson' => (string)$this->option('states-geojson'),
            '--cities-geojson' => (string)$this->option('cities-geojson'),
            '--neighborhoods-geojson' => (string)$this->option('neighborhoods-geojson'),
            '--fail-on-error' => 1,
            '--dry-run' => $dryRun,
        ];

        $commands[] = ['superapp:zone-import-brazil', $zoneCommandArgs];

        foreach ($commands as [$command, $args]) {
            $this->line("Running: {$command}");
            $code = Artisan::call($command, $args);
            $this->output->write(Artisan::output());

            if ($code !== 0) {
                $this->error("Processo interrompido em {$command}.");
                return self::FAILURE;
            }
        }

        $this->info('Concluído: geografia e zonas BR configuradas com sucesso.');

        return self::SUCCESS;
    }
}
