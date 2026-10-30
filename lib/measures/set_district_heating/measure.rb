# Author: Demba Ndiaye

# see the URL below for information on how to write OpenStudio measures
# http://nrel.github.io/OpenStudio-user-documentation/reference/measure_writing_guide/

# start the measure
class SetDistrictHeating < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    return 'Set District Heating'
  end

  # human readable description
  def description
    return 'This measure removes all boilers in a given hot water loop and replaces them with a District Heating object.'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'The District Heating object is set to autosize unless a size is input by the user.'
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    # the hot water loop to add the district heating object to
    hwlp = OpenStudio::Measure::makeChoiceArgumentOfWorkspaceObjects("hwlp", "OS_PlantLoop".to_IddObjectType, model, false)
    hwlp.setDisplayName('Hot Water Loop to Add the District Heating Object to:')
    args << hwlp

    # adding argument for district heating object capacity (in Btu/h)
    dis_heat_cap = OpenStudio::Measure::OSArgument.makeDoubleArgument('dis_heat_cap', false)
    dis_heat_cap.setDisplayName('District Heating Capacity. If 0 or negative, the district heating object will autosize')
    dis_heat_cap.setUnits('Btu/h')
    dis_heat_cap.setDefaultValue(0.0)
    args << dis_heat_cap

    return args
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # use the built-in error checking
    if not runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    # assign the user inputs to variables
    hwlp = runner.getOptionalWorkspaceObjectChoiceValue("hwlp", user_arguments, model)
    dis_heat_cap = runner.getDoubleArgumentValue('dis_heat_cap', user_arguments)

    # check the hot water loop for reasonableness
    if hwlp.empty? # no plant loop was selected, or the plant loop was removed by another measure
      runner.registerError("No hot water loop name was entered, or the hot water loop selected may have been removed by another measure.")
      return false
    else
      if not hwlp.get.to_PlantLoop.empty?
        hwlp = hwlp.get.to_PlantLoop.get
        # verify that the plant loop is an actual hot water loop (i.e. its type is Heating)
        if hwlp.sizingPlant.loopType != "Heating" 
          runner.registerError("Plant loop #{hwlp.name.to_s} is not a hot water loop.")
          return false
        else
          runner.registerInfo("Using plant loop #{hwlp.name.to_s} as hot water loop to apply district heating to.")
        end
      else
        runner.registerError("Script Error - argument not showing up as plant loop.")
        return false
      end
    end

    # remove all boilers from the selected hot water loop
    # first get vectors of all boilers if any (boilers can be of type "HotWater" or "Steam"; in the future, might add water-to-water heat pumps
    # or air-to-water heat pumps that provide hot water for heating)
    boilers_hot_water = hwlp.supplyComponents('OS:Boiler:HotWater'.to_IddObjectType) # boilers of type "HotWater"  
    boilers_steam = hwlp.supplyComponents('OS:Boiler:Steam'.to_IddObjectType) # boilers of type "Steam"
    nb_blrs_hw = boilers_hot_water.size() # total number of boilers of type "HotWater"
    nb_blrs_st = boilers_steam.size() # total number of boilers of type "Steam"
    runner.registerInfo("There are #{nb_blrs_hw.to_s} boilers of type HotWater, and #{nb_blrs_st.to_s} boilers of type Steam associated with the hot water loop.")  
    
    # go over the boilers list, and remove the boiler and its associated supply branch
        # starting with boilers of type "HotWater"
    if nb_blrs_hw > 0 # if, indeed, there are boilers of type "HotWater" in the model
      boilers_hot_water.each do |blr_hw|
        blr_hw = blr_hw.to_BoilerHotWater.get
        # Remove the supply side branch containing the boiler in the hot water loop. Removes at the same time the boiler. 
        hwlp.removeSupplyBranchWithComponent(blr_hw)
        runner.registerInfo("The demand side branch containing boiler #{blr_hw.name.to_s} has been removed from the model.") 
      end # of each do   
    end #finished going over the boiler list for boilers of type "HotWater"

    # starting with boilers of type "Steam"
    if nb_blrs_st > 0 # if, indeed, there are boilers of type "Steam" in the model
      boilers_steam.each do |blr_st|
        blr_st = blr_st.to_BoilerSteam.get
        # Remove the supply side branch containing the boiler in the hot water loop. Removes at the same time the boiler. 
        hwlp.removeSupplyBranchWithComponent(blr_st)
        runner.registerInfo("The demand side branch containing boiler #{blr_st.name.to_s} has been removed from the model.")
      end # of each do     
    end #finished going over the boiler list for boilers of type "Steam"

    # Create a new district heating object
    dist_htg = OpenStudio::Model::DistrictHeating.new(model)

    # Set the capacity of the district heating object, as input by the user (if user did not input any capacity, object will autosize)
    if dis_heat_cap > 0
      dis_heat_cap = OpenStudio.convert(dis_heat_cap, "Btu/h", "W") # conversion of capacity to Watts
      if dis_heat_cap.is_initialized # if the conversion happened without issue
        dis_heat_cap = dis_heat_cap.get # get the value since the conversion produces an Optional::Double variable
        dist_htg.setNominalCapacity(dis_heat_cap)
      else
        runner.registerInfo("The conversion of the district heating capacity to Btu/h did not work. The capacity will be autosized.")
      end
    end

    # Create a new supply branch for the district heating object, attached to the hot water loop
    hwlp.addSupplyBranchForComponent(dist_htg)
    runner.registerInfo("A new branch with a new district heating object has been added to the loop #{hwlp.name}.")
    
    return true
  end #end of run method
end #end of measure

# register the measure to be used by the application
SetDistrictHeating.new.registerWithApplication
