<?php

namespace App\Console\Commands;

use App\Console\Commands\Concerns\SuperappTracksJobs;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

class SuperappZoneSyncModulesCommand extends Command
{
    use SuperappTracksJobs;

    protected $signature = 'superapp:zone-sync-modules {--modules=all} {--dry-run}';
    protected $description = 'Sincroniza vínculos zone_region x módulo (idempotente)';

    public function handle(): int
    {
        $dryRun = (bool)$this->option('dry-run');
        $this->startSuperappJob($this->getName(), 'database', $this->options(), $dryRun);

        $moduleOption = (string)$this->option('modules');
        $moduleIds = strtolower($moduleOption) === 'all'
            ? DB::table('modules')->pluck('id')->all()
            : array_map('intval', array_filter(array_map('trim', explode(',', $moduleOption))));

        $zoneIds = DB::table('zone_regions')->pluck('id');
        foreach ($zoneIds as $zoneId) {
            foreach ($moduleIds as $moduleId) {
                $this->jobStats['processed_rows']++;
                $exists = DB::table('zone_region_modules')
                    ->where('zone_region_id', $zoneId)
                    ->where('module_id', $moduleId)
                    ->exists();

                if (!$dryRun) {
                    DB::table('zone_region_modules')->updateOrInsert(
                        ['zone_region_id' => $zoneId, 'module_id' => $moduleId],
                        ['is_enabled' => 1, 'updated_at' => now(), 'created_at' => now()]
                    );
                }

                $this->jobStats[$exists ? 'updated_rows' : 'inserted_rows']++;
            }
        }

        $manifest = $this->createManifest($this->getName(), ['stats' => $this->jobStats, 'dry_run' => $dryRun]);
        $this->finishSuperappJob('completed', $manifest, 'Zone module sync done');

        return self::SUCCESS;
    }
}
