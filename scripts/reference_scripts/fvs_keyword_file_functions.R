
write.FVSfiles <- function(  trees, stand, 
                             years_out=100, 
                             calibrate=TRUE,
                             triple=FALSE,
                             add_regen=FALSE,
                             customSDImax=NULL,
                             randomseed=2025){
  
  #stand <- standinit
  #trees <- treeinit
  
  # Set variant defaults if stuff is missing
  stand$ASPECT <- ifelse( is.na(stand$ASPECT),  0, stand$ASPECT )        # aspect degrees
  stand$SLOPE <- ifelse( is.na(stand$SLOPE),    5, stand$SLOPE )         # slope percent
  stand$ELEVFT <- ifelse( is.na(stand$ELEVFT ), 38, stand$ELEVFT/100 ) # elevation
  stand$FOREST <- ifelse( is.na(stand$FOREST),  18, stand$FOREST ) 
  
  ### generate file names
  filename <- tempfile(,tmpdir="temp")
  keyfilename <- paste0( filename, ".key")
  treefilename <- paste0( filename, ".tre")
  
  ### write fvs .tre file
  write.fvs.tree.file( trees, stand, treefilename )    
  
  ###
  ### Keyword file creation
  ###
  
  ### stand identification
  write("STDIDENT", file=keyfilename, append=T)  
  write("FVSProjection",  file=keyfilename, append=T)  
  t1 <- sprintf("RANNSEED  %10.0f",randomseed)
  write(t1, file=keyfilename, append=T )

  t1 <- sprintf("STDINFO   %10.1f%10s%10.1f%10.1f%10.1f%10.0f",   
                stand$FOREST, stand$PV_CODE, stand$AGE, stand$ASPECT, stand$SLOPE, stand$ELEVFT )
  write( t1, file=keyfilename, append=T )   
  
  ### site index (not needed for FVSie)
  t1 <- sprintf("SITECODE  %10s%10i%10i", stand$SITE_SPECIES, as.integer(stand$SITE_INDEX+0.5), 1 )
  write(t1, file=keyfilename, append=T)
  
  ### tree list output file (with no headers = column 3 = -1)
  t1 <- "TREELIST           0         3         0         0         0         0         0"    
  write( t1, file=keyfilename, append=T ) 
  
  ### tree list output file (with headers = column 3 = 0)
  t1 <- "TREEFMT"
  t2 <- "(I4,I4,F8.3,I1,A3,F5.1,F5.1,2F5.1,F5.1,I1,6I2,2I1,I2,2I3,2I1,F3.0)"   # use FIA species codes
  
  write( t1, file=keyfilename, append=T )           
  write( t2, file=keyfilename, append=T )          
  write( " ", file=keyfilename, append=T )       
  
  ### sample design
  t1 <- sprintf( "DESIGN          -1.0         0         0%10i         0         0       1.0", stand$NUM_PLOTS  )
  write( t1, file=keyfilename, append=T )           
  
  ### inventory year
  t1 <- sprintf("INVYEAR   %10i", stand$INV_YEAR )
  write( t1, file=keyfilename, append=T )            
  
  # variant default cycle length
  cycle.length <- 10
  cycles <- ceiling( years_out / cycle.length ) 
  
  ### add user supplied reporting years
  t1 <- sprintf("CYCLEAT   %10i", stand$INV_YEAR + years_out )
  write( t1, file=keyfilename, append=T )    
  
  ### bar tripling if necessary
  if (!triple){
    write("NOTRIPLE", file=keyfilename, append=T )
  }
  
  ### ingrowth(regeneration)
  if (!add_regen){
    write( "NOAUTOES", file=keyfilename, append=T)
  } else {
    write( "ESTAB", file=keyfilename, append=T )
    t1 <- sprintf("RANNSEED  %10.0f",randomseed)
    write(t1, file=keyfilename, append=T )
    write( "NOINGROWTH", file=keyfilename, append=T )   
    write( "END", file=keyfilename, append=T )
  }
     
  ### SDI maximum 
  if( !is.null(customSDImax) )
  {
    j <- sprintf("SDIMAX  %10s%10i", SDImax$SP, SDImax$MaxSDI )
    cat( j, sep="\n", file=keyfilename, append=T )
  } 
  
  ## calibration
  t1 <- sprintf("GROWTH    %10.0f%10.0f%10.0f%10.0f%10.0f",
                stand$DG_TRANS,stand$DG_MEASURE,
                stand$HTG_TRANS,stand$HTG_MEASURE,stand$MORT_MEASURE)
  write(t1, file=keyfilename, append=T )
  if (!calibrate){
    write( "NOCALIB", file=keyfilename, append=T)
    write( "NOHTDREG", file=keyfilename, append=T)
  }
  
  # number of cycles 
  t1 <- sprintf("NUMCYCLE  %10i", cycles )
  write(t1, file=keyfilename, append=T ) 
  
  
  write( "PROCESS", file=keyfilename, append=T ) 
  write( "STOP", file=keyfilename, append=T )  
  
  return(filename)
}


write.fvs.tree.file <- function( tl, std, treefilename )
{
  ###
  ### tree list file creation with provision for missing heights and crowns
  ###
  
  # add FVS-specific fields that are connected with regen
  tl$SLOPE <- std$SLOPE 
  tl$ASPECT <- std$ASPECT 
  tl$PV_CODE <- as.numeric(std$PV_CODE)
  tl$TOPOCODE <- as.numeric(tl$TOPOCODE)
  tl$SPREP <- 0
  # add some values that are not used
  tl$TVAL <- 0
  tl$CUT <- 0
  
  # turn crown ratio into a class (see essential fvs p43
  tl$CRcode <- ceiling(tl$CRRATIO/10)
  tl$CRcode <- pmin(tl$CRcode,9)
  tl$CRcode <- pmax(tl$CRcode,1)
  
  # # might need this if processing FIA data
  # tl$DAMAGE1 <- ifelse(!is.na(tl$HTTOPK),97,0)
  # tl$DAMAGE2 <- tl$DAMAGE3 <- tl$SEVERITY1 <- tl$SEVERITY2 <- tl$SEVERITY3 <- 0
  
  # replace missing values with empties
  fvs_formats <- data.frame(tree_var=c("PLOT_ID","fvs.TREE_ID","TREE_COUNT","HISTORY","SPECIES",
                                       "DIAMETER","DG","HT","HTTOPK","HTG","CRcode",
                                       "DAMAGE1","SEVERITY1","DAMAGE2","SEVERITY2","DAMAGE3","SEVERITY3",
                                       "TVAL","CUT","SLOPE","ASPECT","PV_CODE","TOPOCODE","SPREP","AGE"),
                            format=c("%4.0f","%4.0f","%8.3f","%1.0f","%3.0f",
                                     "%5.1f","%5.1f","%5.1f","%5.1f","%5.1f","%1.0f",
                                     "%2.0f","%2.0f","%2.0f","%2.0f","%2.0f","%2.0f",
                                     "%1.0f","%1.0f","%2.0f","%3.0f","%3.0f","%1.0f","%1.0f","%3.0f"))
  fvs_formats$txt_format <- with(fvs_formats,paste(substring(format,1,2),"s",sep=""))
  
  
  for (var in 1:nrow(fvs_formats)){ #fvs_formats$tree_var){
    tl[,fvs_formats$tree_var[var]] <- ifelse(is.na(tl[,fvs_formats$tree_var[var]]),
                                             paste(rep(" ",substring(fvs_formats$format[var],2,2)),collapse=""),
                                             sprintf(fvs_formats$format[var],tl[,fvs_formats$tree_var[var]]))
  }
  tl$SPECIES <- ifelse(as.numeric(tl$SPECIES)<100,
                       paste("0",as.numeric(tl$SPECIES),sep=""),tl$SPECIES)
  
  # write text file
  flat_format <- sprintf(paste(fvs_formats$txt_format,collapse = ""),
                         tl$PLOT_ID,tl$fvs.TREE_ID,tl$TREE_COUNT,tl$HISTORY,tl$SPECIES,
                         tl$DIAMETER,tl$DG,tl$HT,tl$HTTOPK,tl$HTG,tl$CRcode,
                         tl$DAMAGE1,tl$SEVERITY1,tl$DAMAGE2,tl$SEVERITY2,tl$DAMAGE3,tl$SEVERITY3,
                         tl$TVAL,tl$CUT,
                         tl$SLOPE,tl$ASPECT,tl$PV_CODE,tl$TOPOCODE,tl$SPREP,tl$AGE)
  cat(flat_format, file=treefilename, sep="\n")              
  
}
