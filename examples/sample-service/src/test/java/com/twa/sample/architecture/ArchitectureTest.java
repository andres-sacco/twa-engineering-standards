package com.twa.sample.architecture;

import com.tngtech.archunit.core.importer.ImportOption;
import com.tngtech.archunit.junit.AnalyzeClasses;
import com.tngtech.archunit.junit.ArchTest;
import com.tngtech.archunit.junit.ArchTests;
import com.twa.layered.TwaCoreRules;
import com.twa.sample.Application;

/** Reglas de twa-layered-rules, como en los servicios: las lee ARC-01 en los reportes de Surefire. */
@AnalyzeClasses(packagesOf = Application.class, importOptions = ImportOption.DoNotIncludeTests.class)
class ArchitectureTest {
    @ArchTest
    static final ArchTests core = ArchTests.in(TwaCoreRules.class);
}
