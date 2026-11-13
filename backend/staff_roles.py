CLINICAL_ROLES = frozenset({'ward_nurse', 'charge_nurse', 'doctor_on_call'})
SUPPORT_ROLES = frozenset({'pca', 'housekeeper', 'catering', 'fire_marshall'})
PROVISIONABLE_ROLES = CLINICAL_ROLES | SUPPORT_ROLES

# Responsibilities never confer clinical permissions.
RESPONSIBILITIES = {
    'incharge_nurse': ('In-charge nurse', {'ward_nurse', 'charge_nurse'}),
    'team_leader': ('Team leader', {'ward_nurse', 'charge_nurse'}),
    'duty_leader': ('Duty leader', {'ward_nurse', 'charge_nurse'}),
    'discharge_nurse': ('Discharge nurse', {'ward_nurse', 'charge_nurse'}),
    'pca': ('Patient Care Attendant (PCA)', {'pca'}),
    'housekeeper': ('Housekeeper', {'housekeeper'}),
    'catering': ('Catering (Kitchen & Meals)', {'catering'}),
    'fire_marshall': ('Fire Marshal', PROVISIONABLE_ROLES),
}
