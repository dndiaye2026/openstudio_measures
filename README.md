

###### (Automatically generated documentation)

# Set District Cooling

## Description
This measure removes all chillers in a given chilled water loop and replaces them with a District Cooling object.

## Modeler Description
If a chiller in the given CHW loop is attached to a CW loop, the measure removes the chiller from that CW loop. 
    If that CW loop is empty after removing the chiller, the measure removes the CW loop from the model. The District Cooling 
    object is set to autosize unless a size is input by the user. Two limitations of this measure are that: (1) it only 
    considers chillers of type Electric_Eir, and (2) it does not consider condenser loops of type primary-secondary.

## Measure Type
ModelMeasure

## Taxonomy


## Arguments


### Chilled Water Loop to Add the District Cooling Object to:

**Name:** chwlp,
**Type:** Choice,
**Units:** ,
**Required:** false,
**Model Dependent:** false

**Choice Display Names** []


### District Cooling Capacity. If 0 or negative, the district cooling object will autosize

**Name:** dis_cool_cap,
**Type:** Double,
**Units:** Btu/h,
**Required:** false,
**Model Dependent:** false






