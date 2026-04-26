<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

class SuperappAuditScaleCommand extends Command
{
    protected $signature = 'superapp:audit-scale';
    protected $description = 'Audita o progresso da escala nacional e grava superapp_data_quality_reports';

    public function handle(): int
    {
        $targets = [
            'br_states' => 27,
            'br_cities' => 5570,
            'br_neighborhoods' => 350000,
            'postal_code_ranges' => 500000,
            'zone_regions_active' => 25000,
            'zone_regions_surge' => 10000,
            'zone_region_modules' => 210000,
        ];

        $metrics = [];
        $metrics['br_states'] = Schema::hasTable('br_states') ? DB::table('br_states')->count() : 0;
        $metrics['br_cities'] = Schema::hasTable('br_cities') ? DB::table('br_cities')->count() : 0;
        $metrics['br_neighborhoods'] = Schema::hasTable('br_neighborhoods') ? DB::table('br_neighborhoods')->count() : 0;
        $metrics['postal_code_ranges'] = Schema::hasTable('postal_code_ranges') ? DB::table('postal_code_ranges')->count() : 0;
        $metrics['zone_regions_active'] = Schema::hasTable('zone_regions') ? DB::table('zone_regions')->where('zone_type', 'active')->count() : 0;
        $metrics['zone_regions_surge'] = Schema::hasTable('zone_regions') ? DB::table('zone_regions')->where('zone_type', 'surge')->count() : 0;
        $metrics['zone_region_modules'] = Schema::hasTable('zone_region_modules') ? DB::table('zone_region_modules')->count() : 0;

        $status = 'ok';
        foreach ($targets as $k => $target) {
            if (($metrics[$k] ?? 0) < ($target * 0.5)) {
                $status = 'critical';
                break;
            }
            if (($metrics[$k] ?? 0) < $target && $status !== 'critical') {
                $status = 'warning';
            }
        }

        if (Schema::hasTable('superapp_data_quality_reports')) {
            DB::table('superapp_data_quality_reports')->insert([
                'report_name' => 'superapp_scale_audit',
                'metrics' => json_encode(['actual' => $metrics, 'targets' => $targets], JSON_UNESCAPED_UNICODE),
                'notes' => json_encode(['message' => 'Infra baseline audit'], JSON_UNESCAPED_UNICODE),
                'status' => $status,
                'created_at' => now(),
                'updated_at' => now(),
            ]);
        }

        $this->table(['Metric', 'Actual', 'Target'], collect($targets)->map(fn($v, $k) => [$k, $metrics[$k] ?? 0, $v])->values());
        $this->info('Audit status: '.$status);

        return self::SUCCESS;
    }
}
