#!/usr/bin/python3.6

# Author(s): Mackenzie Peterson
# Description:  This file acts as the user control for DNN training, approximate synthesis,
#               exact synthesis, and file I/O.

#MH: Modified to allow sys.argv Feb 18 2020 

import sys
import os
import copy
import time

from pyscripts.synthesisEngine import synthesisEngine
from pyscripts.Utils import printInit, initFiles, getCommand, writeRuntxt, writeRuntxt_power, runABC, checkABCError, is_float, printHelp, writeBlif, printError, trainDNN, setLib, del_unnecessary_files
from shutil import rmtree
#====================================global varaibales======================================
model_name_file = "temp__blif.blif"
#===========================================================================================
# adds tab autocomplete capability ---------------------------------------------------------
try:
	import readline
	readline.set_completer_delims(' \t\n;')
	readline.parse_and_bind("tab: complete")
except ImportError:
	print("Note: Unable to import packages for tab autocomplete. This may happen with OS X\n")

# ------------------------------------------------------------------------------------------

# utilizes the DNN to do approximate synthesis ----------------------------------------------
def mapApprox(command, power):

    validate_error = False
    area = False
    fVerbose = False
    num_iterations = sys.maxsize
    init_command = copy.deepcopy(command)
    parsed_error_constraint = ""
    parsed_command = init_command.split(" ")

    for item in range(0,len(parsed_command)):
        if (parsed_command[item] == "-r"):
            if (item+1 >= len(parsed_command)):
                print("No error constraint specified for \"-r\"")
                return
            parsed_error_constraint = parsed_command[item+1]
        if (parsed_command[item] == "map_approx"):
            command = parsed_command[item+1]
        if (parsed_command[item] == "-val"):
            #print("\nValiating Error during synthesis...\n")
            validate_error = True
        if (parsed_command[item] == "-a"):
            #print("\nOptimizing area at end of Synthesis...\n")
            area = True
        if (parsed_command[item] == "-v"):
            fVerbose = True
        if (parsed_command[item] == "-i"):
            if (item+1 >= len(parsed_command)):
                print("No specified number of iterations for \"-i\"")
                return
            if (parsed_command[item+1].isdigit() == 0):
                print("Specified number of iterations is not an integer")
                return
            num_iterations = parsed_command[item+1]

    # checks that the user_error_constraint is of type float before continuing
    if(is_float(parsed_error_constraint)):
        user_error_constraint = float(parsed_error_constraint)
        if (user_error_constraint <= 0.001):
            temp = init_command.split(" ")
            temp.pop(0)
            temp.pop(-1)
            new_command = ""
            for item in temp:
                new_command = new_command + item + " "
            print("\nError Rate must be above 0.001, mapping exact network..")
            mapExact(new_command)
            return
    else:
        print("ERROR: map_approx should have a valid error constraint between 0.0 and 1.0")
        print("\t map_approx    <file_path (.blif or .bench)>   -r <error constraint (0.0 - 1.0)>")
        return

    if ((".bench" not in command and ".blif" not in command) or len(command)<=6):
        print("ERROR: invalid filetype for map_approx\n")
        return

    writeRuntxt(command)
    map_start = time.time()
#    print("\n calling runABC()")
    runABC()
    map_end = time.time()

    # extracts information about the nodes for approximate synthesis
    extract_command = "python3.6 pyscripts/blif_to_custom_bench.py > original.bench"
    os.system(extract_command)
    extract_command = "python3.6 pyscripts/node_extract.py original.bench"
    os.system(extract_command)

    # checks that the filename is correct and that ABC was able to successfully map
    if(not checkABCError(command)):
        if(fVerbose):
            print("\nExact Network:")
        network = synthesisEngine(error_constraint=user_error_constraint)
        network.loadLibraryStats()
        network.loadNetwork()
        if(fVerbose):
            network.printGates()
        network.getCritPath()
        if(power):
            if(fVerbose):
                network.printCritPowerNodes()
            init_power = network.calcTotalPower()
        else:
            if(fVerbose):
                network.printCritPath()
        init_delay = network.calcDelay(1)
        init_area = network.calcArea(1)
        start = time.time()
        if(power):
            network.approxPower(validate_error=validate_error, fVerbose=fVerbose, max_iter=num_iterations)
        else:
            network.approxDelay(validate_error=validate_error, fVerbose=fVerbose, max_iter=num_iterations)
        if (area):
            network.areaClean(validate_error=validate_error, fVerbose=fVerbose,  max_iter=num_iterations)
        end = time.time()
        error = network.calcOutputError()
        repl_delay = network.calcDelay(1)
        repl_area = network.calcArea(1)
        repl_power = network.calcTotalPower()
        #network.getCritPath()
        if(fVerbose):
            network.writeNodeTypes()

        # get the error at all outputs
        command = "error/error -all"
        os.system(command)

        #start = time.time()
        system_call = "python3.6 pyscripts/node_types_to_blif.py"
        os.system(system_call)
        system_call = "python3.6 pyscripts/custom_bench_to_blif.py original.bench > temp.blif"
        os.system(system_call)
        
        #running ABC for the last time for final optimization:
        if (power):
            writeRuntxt_power("temp.blif")
        else:
            writeRuntxt("temp.blif")
        runABC()

        extract_command = "python3.6 pyscripts/blif_to_custom_bench.py > original.bench"
        os.system(extract_command)
        extract_command = "python3.6 pyscripts/node_extract.py original.bench"
        os.system(extract_command)
        os.system("rm temp.blif")
        #end = time.time()

        if(fVerbose):
            print("\n\nApproximated Network:")
        network.reset()
        network.loadLibraryStats()
        network.loadNetwork()
        network.calcArea(1)
        if(fVerbose):
            network.printGates()
        network.getCritPath()
        if(power):
            if(fVerbose):
                network.printCritPowerNodes()
        else:
            if(fVerbose):
                network.printCritPath()
        final_delay = network.calcDelay(1)
        final_area = network.calcArea(1)
        total_power = network.calcTotalPower()

        print("run-time (seconds):", round(end - start,6))

        print("Results:")
        print("----------------------------------")
        if(power):
            print("Initial switching power:   |  %.2f" %init_power)
        #else:
        print("Initial Critical Delay:    | ", init_delay)
        print("Initial Area:              | ", init_area)
        print("----------------------------------")
        print("PreMap switching power:    |  %.2f" %repl_power)
        print("PreMap Critical Delay:     | ", repl_delay)
        print("PreMap Area:               | ", repl_area)
        print("----------------------------------")
        if(power):
            print("Final switching power:     |  %.2f" %total_power)
        #else:
        print("Final Critical Delay:      | ", final_delay)
        print("Final Area:                | ", final_area)
        print("----------------------------------")
        print("Error Rate:                | ", error)


# map the exact network using abc -----------------------------------------------------------
def mapExact(command):
    # ensure the argument is valid
    command_list = command.split(" ") 
    if(len(command_list)!=2):
        print("ERROR: map_approx should have one argument\n")
        return
    for item in command_list:
        if("map_exact" in item):
            command_list.remove(item)
    command = command_list[0]
    if ((".bench" not in command and ".blif" not in command) or len(command)<=6):
        print("ERROR: invalid filetype for map_exact\n")
        return

    writeRuntxt(command)
    runABC()
    # write to original.bench in case user wants to write_blif
    os.system("python3.6 pyscripts/blif_to_custom_bench.py > original.bench")
    extract_command = "python3.6 pyscripts/node_extract.py original.bench"
    os.system(extract_command)

    print("\nExact Network:")
    network = synthesisEngine(error_constraint=0)
    network.loadLibraryStats()
    network.loadNetwork()
    network.printGates()
    network.getCritPath()
    network.printCritPath()
    network.calcOutputError()
    final_delay = network.calcDelay(1)
    final_area = network.calcArea(1)
    total_power = network.calcTotalPower()
    command = "error/error -all"
    os.system(command)
    print("\nNetwork has been mapped with:")
    print("Final switching power:     |  %.2f" %total_power)
    print("Final Critical Delay:      | ", final_delay)
    print("Final Area:                | ", final_area)
    print("Average error:\t0%\n")


# handles and distributes the commands from the user to their respective functions -----------
def commandHandler(command):
    global model_name_file
    exit_list = ["quit", "exit", "q"]
    if (command == ""):
        return
    elif ("help" in command or command == "h"):
        printHelp()
    elif ("map_approx" in command):
        if("-p" in command):
            command = command.replace("-p", "")
            #print(command)
            mapApprox(command, 1)
        else:
            mapApprox(command, 0)
    elif ("map_exact" in command):
        mapExact(command)
    elif ("write_blif" in command):
        model_name = command.split(" ")
        model_name = model_name[1]
        model_name = model_name.lstrip()
        model_name = model_name.rstrip()
        blif_file = model_name
        model_name = model_name.split(".")
        model_name = model_name[0]
        model_name_file = model_name + ".blif"
        writeBlif(command, 1, model_name)
        #save this blif file 
        path = "temp_blif"
        #if os.path.exists(path): rmtree(path)
        if os.path.exists(path) is False:
            os.makedirs(path)
        os.system("cp " + blif_file + " " + path)
    elif ("print_error" in command):
        printError()
    elif ("train_dnn" in command):
        trainDNN()
    elif ("read_library" in command):
        setLib(command)
    elif ("show -g" in command):
        print("Before calling this command, write_blif should have been invoked!")
        file = open("run.txt", "w")
        file.write("read_library tech_lib/techlib.genlib \n")
        file.write("read " + model_name_file + "\n")
        file.write("show -g\n")
        file.close()
        runABC()
        print("Please go and open " + model_name_file[:-5] + ".dot")
    elif (command not in exit_list):
        print("Command not recognized, type \"help\" for a list of commands\n")

# ------------------------------------------------------------------------------------------
def main():
    os.system("cp abc/abc.rc .")
    initFiles()  
    if len(sys.argv) == 1:
     printInit()
     command = ""
     exit_list = ["quit", "exit", "q"]
     while(command not in exit_list):
      command = getCommand()
      commandHandler(command)
    else: 
     command = ""
     exit_list = ["quit", "exit", "q"]
     while(command not in exit_list):
        command = sys.argv[1]
        sys.argv[1] ="quit" 
        commandHandler(command)
    # unnecessary file removal
    del_unnecessary_files()
    
if __name__ == "__main__":
    main()
