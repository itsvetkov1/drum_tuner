add_executable(dsp_core_tests
    smoke_test.cpp
)

target_link_libraries(dsp_core_tests PRIVATE dsp_core)

add_test(NAME dsp_core_tests COMMAND dsp_core_tests)
