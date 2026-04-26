<?php

namespace App\Console;

use Illuminate\Console\Scheduling\Schedule;
use Illuminate\Foundation\Console\Kernel as ConsoleKernel;

class Kernel extends ConsoleKernel
{
    /**
     * The Artisan commands provided by your application.
     *
     * @var array
     */
    protected $commands = [
        \App\Console\Commands\CreateZoneCommand::class,
        \App\Console\Commands\AttachModulesToZoneCommand::class,
        \App\Console\Commands\CatalogSeedCommand::class,
        \App\Console\Commands\AttributeSeedCommand::class,
        \App\Console\Commands\ParcelCategorySeedCommand::class,
        \App\Console\Commands\SeedDmVehiclesCommand::class,
        \App\Console\Commands\SuperappExportCommand::class,
        \App\Console\Commands\SuperappGeoImportStatesCommand::class,
        \App\Console\Commands\SuperappGeoImportCitiesCommand::class,
        \App\Console\Commands\SuperappGeoImportNeighborhoodsCommand::class,
        \App\Console\Commands\SuperappGeoImportPostalCodesCommand::class,
        \App\Console\Commands\SuperappZoneBuildCommand::class,
        \App\Console\Commands\SuperappZoneSyncModulesCommand::class,
        \App\Console\Commands\SuperappCatalogExpandCommand::class,
        \App\Console\Commands\SuperappSkuImportCommand::class,
        \App\Console\Commands\SuperappAuditScaleCommand::class,
        \App\Console\Commands\SuperappLaunchMassiveSetupCommand::class,
    ];

    /**
     * Define the application's command schedule.
     *
     * @param  \Illuminate\Console\Scheduling\Schedule  $schedule
     * @return void
     */
    protected function schedule(Schedule $schedule)
    {
        // $schedule->command('inspire')->hourly();
    }

    /**
     * Register the commands for the application.
     *
     * @return void
     */
    protected function commands()
    {
        $this->load(__DIR__.'/Commands');

        require base_path('routes/console.php');
    }
}
