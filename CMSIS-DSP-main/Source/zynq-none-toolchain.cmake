set(CMAKE_SYSTEM_NAME 		"Generic" 		CACHE STRING "")
 
set(CMAKE_SYSTEM_PROCESSOR 	"arm" 			CACHE STRING "")
 
SET(CMAKE_CROSSCOMPILING 1)
 
 
 
set(CMAKE_C_COMPILER_WORKS 1)
 
set(CMAKE_CXX_COMPILER_WORKS 1)
 
 
 
set(CROSS_PREFIX            "arm-none-eabi-"    CACHE STRING "")
 
set(CMAKE_C_FLAGS           "-mcpu=cortex-a9 -mfpu=vfpv3 -mfloat-abi=hard"	CACHE STRING "")
 
set(CMAKE_CXX_FLAGS         "-mcpu=cortex-a9 -mfpu=vfpv3 -mfloat-abi=hard"	CACHE STRING "")
 
 
 
include (CMakeForceCompiler)
 
set(CMAKE_ASM_COMPILER 		"${CROSS_PREFIX}as")
 
set(CMAKE_C_COMPILER 		"${CROSS_PREFIX}gcc")
 
set(CMAKE_CXX_COMPILER 		"${CROSS_PREFIX}g++")
 
set(CMAKE_LINKER 			"${CROSS_PREFIX}gcc")
 
 
 
set (CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER CACHE STRING "")
 
set (CMAKE_FIND_ROOT_PATH_MODE_LIBRARY NEVER CACHE STRING "")
 
set (CMAKE_FIND_ROOT_PATH_MODE_INCLUDE NEVER CACHE STRING "")
 
 
 
set(CMAKE_NO_SYSTEM_FROM_IMPORTED ON)