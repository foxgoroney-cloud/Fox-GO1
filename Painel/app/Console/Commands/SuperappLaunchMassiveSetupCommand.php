<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;
use Illuminate\Support\Facades\Artisan;

class SuperappLaunchMassiveSetupCommand extends Command
{
    protected $signature = 'superapp:launch-massive-setup {--dry-run}';
    protected $description = 'Executa pipeline massivo Brasil Superapp em sequência';

    public function handle(): int
    {
        $dryRun = (bool)$this->option('dry-run');

        $commands = [
            ['superapp:geo-import-states', ['--source' => 'ibge', '--dry-run' => $dryRun]],
            ['superapp:geo-import-cities', ['--source' => 'ibge', '--state' => 'all', '--dry-run' => $dryRun]],
            ['superapp:geo-import-neighborhoods', ['--source' => 'csv', '--file' => 'storage/imports/neighborhoods.csv', '--dry-run' => $dryRun]],
            ['superapp:geo-import-postal-codes', ['--source' => 'csv', '--file' => 'storage/imports/postal_codes.csv', '--dry-run' => $dryRun]],
            ['superapp:zone-build', ['--strategy' => 'city_cluster', '--target-active' => 25000, '--target-surge' => 10000, '--dry-run' => $dryRun]],
            ['superapp:zone-sync-modules', ['--modules' => 'all', '--dry-run' => $dryRun]],
            ['superapp:catalog-expand', ['--module-types' => 'food,grocery,pharmacy,ecommerce,parcel', '--dry-run' => $dryRun]],
            ['superapp:sku-import', ['--source' => 'csv', '--file' => 'storage/imports/skus.csv', '--chunk' => 5000, '--dry-run' => $dryRun]],
            ['superapp:audit-scale', []],
            ['superapp:export-all', []],
        ];

        foreach ($commands as [$command, $args]) {
            $this->line("Running: {$command}");
            $code = Artisan::call($command, $args);
            $this->output->write(Artisan::output());

            if ($code !== 0) {
                $this->error("Pipeline stopped at {$command}.");
                return self::FAILURE;
            }
        }

        $this->info('Massive setup pipeline completed.');
        return self::SUCCESS;
    }
}
