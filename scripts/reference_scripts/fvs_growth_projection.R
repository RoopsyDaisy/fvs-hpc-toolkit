# 0 initialize things - change paths to match your machine

# file path to FVS on your machine (needed to find rFVS library and binaries)
fvs_path <- file.path("C:","FVS","FVSSoftware")  # <- CHANGE THIS

# path to FVS binaries (should work if you set line 4)
fvs_bin <- file.path(fvs_path,"FVSbin")

# path to rFVS library (may need to change R version directory in next line)
library("rFVS", lib.loc = file.path(fvs_path,"R","R-4.5.0","library")) # <- CHECK THIS

# path to input data
fvs_ready_data <- file.path("R:","Classes","FORS591","Data","Lubrecht_PlotData_FVS") # <- CHANGE THIS

# path to some fvs keyword file generating functions
source(file.path("R:","Classes","FORS591","Data","rFVS_scripts","fvs_keyword_file_functions.R")) # <- CHANGE THIS

# create a temp directory in current path
dir.create("temp")

# function for getting tree lists from FVS
# cf: https://github.com/USDAForestService/ForestVegetationSimulator/wiki/rFVS (down near the bottom)
fetchTrees <- function(){
  tree_list <- fvsGetTreeAttrs(c("id","plot","age","species","dbh","ht","cratio","tpa","mcuft","bdft"))
  tree_list$year <- fvsGetEventMonitorVariables("year")
  tree_list
}

# 1 read the Lubrecht 2023 or format your own data to work
library(readxl)
FVS_TreeInit <- as.data.frame(read_xlsx(file.path(fvs_ready_data,"FVS_Lubrecht_2023.xlsx"),sheet="FVS_TreeInit"))
FVS_StandInit <- as.data.frame(read_xlsx(file.path(fvs_ready_data,"FVS_Lubrecht_2023.xlsx"),sheet="FVS_StandInit"))



# 2 set some FVS projection parameters
num_years <- 55 # number of years into the future to project
use_tripling <- FALSE
use_calibration <- TRUE
use_regenmodel <- FALSE

# 3 pick a particular plot to project, or nest the rest of this script into a for loop
i <- 10

# grab the stand and tree data
standinit <- FVS_StandInit[i,]
treeinit <- FVS_TreeInit[FVS_TreeInit$STAND_ID==standinit$STAND_ID,]

# load the FVS variant binaries
fvsLoad( "FVSie", fvs_bin )

# assign consecutive tree numbers for linking (or FVS will do this
#  by itself and it will be hard to link things up later)
treeinit$fvs.TREE_ID <- 1:nrow(treeinit)

# create FVS keyword and tree list input files
filename <- write.FVSfiles(trees=treeinit,
                           stand=standinit,
                           years_out=num_years,
                           calibrate=use_calibration,
                           triple=use_tripling,
                           add_regen=use_regenmodel) #SDImax=SDImax,

# grow the stand by passing a keyword text file
fvsSetCmdLine(paste0("--keywordfile=",filename,".key"))

# get grown tree list and the summary
fvs_output <- fvsInteractRun(AfterEM1="fetchTrees()",
                             SimEnd=fvsGetSummary) 
names(fvs_output)

# combine the tree lists and map the species from variant specific to FIA
spp <- as.data.frame(fvsGetSpeciesCodes())
spp$spp_num <- 1:nrow(spp)

fvs_tree_list <- NULL 
for (j in 1:(length(fvs_output)-1)){
  new_trees <- fvs_output[[j]]$AfterEM1
  new_trees <- merge(new_trees,spp,
                     by.x="species",by.y="spp_num")
  fvs_tree_list <- rbind(fvs_tree_list,new_trees)
}

# basic summary output
stand_summary <- fvs_output[[length(fvs_output)]]

# end projection
fvsLoad( "FVSie", fvs_bin )

# clean up temp files
file.remove(paste0(filename, c(".key",".tre",".trl",".out") ))

# save or append tree list and summaries
head(fvs_tree_list)
head(stand_summary)
