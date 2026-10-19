# Author: Demba Ndiaye

# see the URL below for information on how to write OpenStudio measures
# http://nrel.github.io/OpenStudio-user-documentation/reference/measure_writing_guide/

# start the measure
class SetDistrictCooling < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    # Measure name should be the title case of the class name.
    return 'Set District Cooling'
  end

  # human readable description
  def description
    return 'This measure removes all chillers in a given chilled water loop and replaces them with a District Cooling object.'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'If a chiller in the given CHW loop is attached to a CW loop, the measure removes the chiller from that CW loop. 
    If that CW loop is empty after removing the chiller, the measure removes the CW loop from the model. The District Cooling 
    object is set to autosize unless a size is input by the user. Two limitations of this measure are that: (1) it only 
    considers chillers of type Electric_Eir, and (2) it does not consider condenser loops of type primary-secondary.'
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    # the chilled water loop to add the district cooling object to
    chwlp = OpenStudio::Measure::makeChoiceArgumentOfWorkspaceObjects("chwlp", "OS_PlantLoop".to_IddObjectType, model, false)
    chwlp.setDisplayName('Chilled Water Loop to Add the District Cooling Object to:')
    args << chwlp

    # adding argument for district cooling object capacity (in Btu/h)
    dis_cool_cap = OpenStudio::Measure::OSArgument.makeDoubleArgument('dis_cool_cap', false)
    dis_cool_cap.setDisplayName('District Cooling Capacity. If 0 or negative, the district cooling object will autosize')
    dis_cool_cap.setUnits('Btu/h')
    dis_cool_cap.setDefaultValue(0.0)
    args << dis_cool_cap

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
    chwlp = runner.getOptionalWorkspaceObjectChoiceValue("chwlp", user_arguments, model)
    dis_cool_cap = runner.getDoubleArgumentValue('dis_cool_cap', user_arguments)

    # check the chilled water loop for reasonableness
    if chwlp.empty? # no plant loop was selected, or the plant loop was removed by another measure
      runner.registerError('No chilled water loop name was entered, or the chilled water loop selected may have been removed by another measure.')
      return false
    else
      if not chwlp.get.to_PlantLoop.empty?
        chwlp = chwlp.get.to_PlantLoop.get
        # verify that the plant loop is an actual chilled water loop (i.e. its type is Cooling)
        if chwlp.sizingPlant.loopType != "Cooling" 
          runner.registerError("Plant loop #{chwlp.name.to_s} is not a chilled water loop.")
          return false
        else
          runner.registerInfo("Using plant loop #{chwlp.name.to_s} as chilled water loop to apply district cooling to.")
        end
      else
        runner.registerError("Script Error - argument not showing up as plant loop.")
        return false
      end
    end

    # remove all chillers from the selected chilled water loop
    # first get a vector of all chiller_electric_eir if any (deals only with Chiller:Electric:EIR for now; could use other types of chillers in the future)
    chillers_electric_eir = chwlp.supplyComponents('OS:Chiller:Electric:EIR'.to_IddObjectType)
    nb_chl = chillers_electric_eir.size()
    runner.registerInfo("There are #{nb_chl.to_s} chillers of type Electric:EIR associated to the chilled water loop.")  
    # go over the chillers list, remove the condenser loop if any, and finally remove the chiller and its associated supply branch
    cw_loop = nil
    chillers_electric_eir.each do |chl_eir|
      chl_eir = chl_eir.to_ChillerElectricEIR.get
      
      # if there is a condenser water loop associated to the chiller, remove that condenser water loop
      cw_loop = chl_eir.condenserWaterLoop
      if cw_loop != nil
        associated_cw_loop = cw_loop.get
        runner.registerInfo("The CW loop associated to chiller #{chl_eir.name.to_s} is #{associated_cw_loop.name.to_s}.") 
        associated_cw_loop.removeDemandBranchWithComponent(chl_eir) # remove, from the CW loop, the demand side branch that contains this chiller
        
        # Add here in the future the case where the CW loop is a secondary condenser water loop that is served by a primary condenser water loop
        # through a heat exchanger (OS:HeatExchanger:FluidtoFluid). In this case, one must get the supply components vector and proceed as with
        # the chiller, i.e. get the associated supply side loop (primary CW loop), and remove the demand side branch there, and if that primary
        # CW loop has no more demand side branch, remove that primary CW loop from the model.  
        
        dem_comp_chlr = associated_cw_loop.demandComponents('OS:Chiller:Electric:EIR'.to_IddObjectType) # demand side components of type chiller_electric_eir 
        # May wanna consider other types of chillers here as well (demandComponents include the nodes and splitters/mixers as well, and will not be empty in this case, 
        # and hence, the reason to look specifically for chillers and heat exchangers. One other way would be to check whether the vector has other component than nodes
        # and splitters/mixers. Another way is to get the demand inlet and outlet nodes and look for demand components between those two nodes.)
        dem_comp_hxch = associated_cw_loop.demandComponents('OS:HeatExchanger:FluidtoFluid'.to_IddObjectType) # demand side components of type heat_exchanger_fluid_to_fluid
        if (dem_comp_chlr.empty?) and (dem_comp_hxch.empty?)  # if the CW loop has no more demand side components of type chiller or heat exchanger, then remove it from the model
          associated_cw_loop.remove
          runner.registerInfo("Condenser water loop #{associated_cw_loop.name.to_s} has no more demand side components, and has been removed from the model.")
        end

        # Now, remove the supply side branch containing the chiller in the chilled water loop. Removes at the same time the chiller. 
        chwlp.removeSupplyBranchWithComponent(chl_eir)
        runner.registerInfo("The demand side branch containing chiller #{chl_eir.name.to_s} has been removed from the model.")
        
      end # of cw_loop not empty
      cw_loop = nil #re-initializing the variable

    end #finished going over the chiller list

    # Create a new district cooling object
    dist_Clg = OpenStudio::Model::DistrictCooling.new(model)

    # Set the capacity of the district cooling object, as input by the user (if user did not input any capacity, object will autosize)
    if dis_cool_cap > 0
      dis_cool_cap = OpenStudio.convert(dis_cool_cap, "Btu/h", "W") # conversion of capacity to Watts
      if dis_cool_cap.is_initialized # if the conversion happened without issue
        dis_cool_cap = dis_cool_cap.get # get the value since the conversion produces an Optional::Double variable
        dist_Clg.setNominalCapacity(dis_cool_cap)
      else
        runner.registerInfo("The conversion of the district cooling capacity to Btu/h did not work. The capacity will be autosized.")
      end
    end

    # Create a new supply branch for the district cooling object, attached to the chilled water loop
    chwlp.addSupplyBranchForComponent(dist_Clg)
    runner.registerInfo("A new branch with a new district cooling object has been added to the loop #{chwlp.name}.")
    
    return true
  end #end of run method
end #end of measure

# register the measure to be used by the application
SetDistrictCooling.new.registerWithApplication
